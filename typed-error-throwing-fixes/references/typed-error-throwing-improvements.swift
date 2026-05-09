import Foundation

// Swift Error Throwing Improvements
// ==================================
//
// Checked with Apple Swift 6.3.1 on 2026-05-09.
//
// This playground documents current rough edges around Swift typed throws,
// especially where typed throws meets Swift Concurrency.
//
// The intentionally broken examples are kept in comments so the playground
// remains usable. Uncomment individual blocks to reproduce the compiler errors.
//
// Primary references:
// - SE-0413 Typed throws:
//   https://github.com/swiftlang/swift-evolution/blob/main/proposals/0413-typed-throws.md
// - SE-0520 Discardable result use in Task initializers:
//   https://github.com/swiftlang/swift-evolution/blob/main/proposals/0520-discardableresult-task-initializers.md
// - Swift issue #76169, async let does not preserve typed throw:
//   https://github.com/swiftlang/swift/issues/76169
// - Swift issue #74555, exhaustive catch statements not detected:
//   https://github.com/swiftlang/swift/issues/74555
// - Swift issue #75430, typed throws inference with generics/autoclosures:
//   https://github.com/swiftlang/swift/issues/75430
// - Swift Forums, withCheckedThrowingContinuation and typed errors:
//   https://forums.swift.org/t/withcheckedthrowingcontinuation-and-typed-errors/72502
// - Swift Forums, FullTypedThrows status:
//   https://forums.swift.org/t/where-is-fulltypedthrows/72346
// - Swift Forums, typed throws in the Concurrency module:
//   https://forums.swift.org/t/pitch-typed-throws-in-the-concurrency-module/68210
// - Swift Forums, continuation typed throws / nonisolated(nonsending) pre-pitch:
//   https://forums.swift.org/t/pre-pitch-updating-with-checked-unsafe-continuation-to-support-typed-throws-and-perhaps-nonisolated-nonsending/84770
//
// Status snapshot:
// - SE-0413 is implemented in Swift 6.0, but the "FullTypedThrows" inference
//   work was not completed for Swift 6 and is future/upcoming-feature work.
// - SE-0520 is accepted. Implementation PR #87439 was merged to main on
//   2026-04-22, after Swift 6.3.1, so treat it as main/unreleased here.
// - Task initializer typed throws adoption was attempted and reverted/deferred
//   because of source compatibility regressions.
// - Concurrency-module typed throws adoption is ongoing and piecemeal.
//
// Table of contents:
// - 1. async let does not preserve typed throws: line 60
// - 1b. Multiple async let values and tuple await: line 128
// - 2. Task initializers erase typed throws: line 194
// - 3. Task silently swallows errors when the handle is discarded: line 280
// - 4. withCheckedThrowingContinuation cannot create typed continuations: line 328
// - 5. Closure typed throws inference is incomplete: line 432
// - 6. do-catch often exposes any Error unless do throws(E) is explicit: line 478
// - 7. Exhaustive catch over a typed error enum is not recognized: line 509
// - 8. Multiple concrete error types collapse to any Error: line 561
// - 9. withThrowingTaskGroup uses any Error: line 643
// - 10. CancellationError does not fit typed domain errors automatically: line 718
// - 11. Result.get() as a typed error tunnel: line 758
// - 12. sending / Sendable and typed errors: line 778
// - Shared Types: line 818
// - Shared Workaround Helpers: line 852

// MARK: - 1. async let does not preserve typed throws

// Problem:
// SE-0413 describes async let as preserving the typed error of its initializer.
// Swift 6.3.1 still widens the awaited value to any Error.
//
// Known status:
// - Open Swift issue #76169: "Async let does not preserve typed throw".
// - In the 2026 continuation pre-pitch, Konrad Malawski noted this is more
//   work than simply updating Concurrency library signatures.
//
// Expected in a statically typed model:
// `try await user` should be accepted in a function declared
// `async throws(ExampleError)`.

/*
func broken_asyncLet_widensToAnyError() async throws(ExampleError) -> User {
    async let user = failWithExampleError()
    return try await user
    // Swift 6.3.1:
    // error: thrown expression type 'any Error' cannot be converted to error type 'ExampleError'
}
*/

// Workaround A, preferred:
// Carry errors through a typed Result channel. This is useful when a concurrency
// boundary widens the thrown error type but preserves a normal value type.

func workaround_asyncLet_resultTunnel() async throws(ExampleError) -> User {
    async let result: Result<User, ExampleError> = asyncResult { () async throws(ExampleError) in
        try await failWithExampleError()
    }

    return try await result.get()
}

// Workaround B, situational:
// Avoid async let for the typed boundary and use sequential await if concurrency
// is not needed. This keeps the error type intact, but it is only applicable
// when losing parallelism is acceptable.

func workaround_asyncLet_avoidWhenNotNeeded() async throws(ExampleError) -> User {
    try await failWithExampleError()
}

// Workaround C, disfavored:
// Await inside an untyped do block and force the error back into the desired
// domain.
//
// This helper uses `as!` internally. That means the compiler is no longer
// proving that only `ExampleError` can cross this boundary. Instead, we are
// asserting it at runtime and accepting a crash if some other error slips
// through. That is especially fragile around concurrency boundaries because a
// future refactor can add a new throwing call inside the body and the force-cast
// will still compile.
//
// In other words: this is useful to demonstrate the shape of the compiler
// limitation, but it is not a serious live-project solution. Production code
// should prefer a typed Result tunnel or an explicit error-mapping boundary
// where every incoming error is handled deliberately.

func workaround_asyncLet_forceError() async throws(ExampleError) -> User {
    try await forceError(ExampleError.self) {
        async let user = failWithExampleError()
        return try await user
    }
}

// MARK: - 1b. Multiple async let values and tuple await

// Problem:
// The same async-let typed-throws loss appears when awaiting several child
// values at once. This is a common shape for independent parallel loads:
//
//     return try await (profile, settings, permissions)
//
// Each tuple element is treated as potentially throwing `any Error`, even if
// each async-let initializer calls a function declared as `throws(ExampleError)`.

/*
func broken_multipleAsyncLet_tupleAwait() async throws(ExampleError) -> (User, User, User) {
    async let a = failWithExampleError()
    async let b = failWithExampleError()
    async let c = failWithExampleError()

    return try await (a, b, c)
    // Swift 6.3.1 reports the same error for each tuple element:
    // error: thrown expression type 'any Error' cannot be converted to error type 'ExampleError'
}
*/

// Workaround A, preferred:
// Use typed Result values as the async-let payload, then call typed `get()` at
// the tuple boundary. This keeps the parallelism and preserves ExampleError.

func workaround_multipleAsyncLet_resultTuple() async throws(ExampleError) -> (User, User, User) {
    async let a: Result<User, ExampleError> = asyncResult { () async throws(ExampleError) in
        try await failWithExampleError()
    }
    async let b: Result<User, ExampleError> = asyncResult { () async throws(ExampleError) in
        try await fetchUser()
    }
    async let c: Result<User, ExampleError> = asyncResult { () async throws(ExampleError) in
        try await fetchUser()
    }

    return try await (a.get(), b.get(), c.get())
}

// Workaround B, situational:
// Sequential await avoids the async-let boundary, but also gives up parallelism.

func workaround_multipleAsyncLet_sequential() async throws(ExampleError) -> (User, User, User) {
    let a = try await failWithExampleError()
    let b = try await fetchUser()
    let c = try await fetchUser()

    return (a, b, c)
}

// Workaround C, disfavored:
// `forceError` can make the tuple await compile, but it is still a force-cast
// based adapter and should not be a serious live-project recommendation.

func workaround_multipleAsyncLet_forceError() async throws(ExampleError) -> (User, User, User) {
    try await forceError(ExampleError.self) {
        async let a = failWithExampleError()
        async let b = fetchUser()
        async let c = fetchUser()

        return try await (a, b, c)
    }
}

// MARK: - 2. Task initializers erase typed throws

// Problem:
// `Task { try await ... }` currently creates `Task<Success, any Error>` for a
// throwing operation. You cannot create a `Task<Success, ExampleError>` using
// the public Task initializer in Swift 6.3.1.
//
// Known status:
// - Task typed throws adoption was attempted.
// - SE-0520 review notes it was reverted due to source compatibility regressions.
// - PR #86358 was closed/deferred; related evolution work is ongoing.

/*
func broken_task_erasesTypedError() {
    let task = Task {
        try await failWithExampleError()
    }

    let typedTask: Task<User, ExampleError> = task
    // Swift 6.3.1:
    // error: cannot assign value of type 'Task<User, any Error>' to type 'Task<User, ExampleError>'
}

func broken_task_cannotForceTypedInitializer() {
    let task: Task<User, ExampleError> = Task {
        () async throws(ExampleError) in
        try await failWithExampleError()
    }
    // Swift 6.3.1:
    // error: referencing initializer 'init(name:priority:operation:)' on 'Task'
    // requires the types 'ExampleError' and 'any Error' be equivalent

    _ = task
}
*/

// Workaround:
// Put a Result in Task's Success channel and make Task itself non-throwing.

func workaround_task_resultTunnel() async throws(ExampleError) -> User {
    let task: Task<Result<User, ExampleError>, Never> = Task {
        await asyncResult { () async throws(ExampleError) in
            try await failWithExampleError()
        }
    }

    return try await task.value.get()
}

// Helper:
// A small typed task wrapper can hide the Result tunnel. It does not make
// Swift's Task typed-throwing; it only restores a typed throwing value API.

struct TypedTask<Success: Sendable, Failure: Error & Sendable>: Sendable {
    private let task: Task<Result<Success, Failure>, Never>

    init(
        priority: TaskPriority? = nil,
        operation: @Sendable @escaping () async throws(Failure) -> Success
    ) {
        task = Task(priority: priority) {
            await asyncResult { () async throws(Failure) in
                try await operation()
            }
        }
    }

    var value: Success {
        get async throws(Failure) {
            try await task.value.get()
        }
    }

    func cancel() {
        task.cancel()
    }
}

func workaround_task_typedWrapper() async throws(ExampleError) -> User {
    let task = TypedTask<User, ExampleError> { () async throws(ExampleError) in
        try await failWithExampleError()
    }

    return try await task.value
}

// MARK: - 3. Task silently swallows errors when the handle is discarded

// Problem:
// In Swift 6.3.1, discarding a throwing unstructured Task does not require you
// to handle the error. The error lives in task.value, but the handle is gone.
//
// Known status:
// - SE-0520 is accepted.
// - Implementation PR #87439 was merged to main on 2026-04-22.
// - Swift 6.3.1 was released before that, so this is likely unreleased in the
//   local toolchain used for this playground.
//
// Expected future behavior:
// Discarding a throwing unstructured Task should produce a warning.

func currentlyAllowed_taskErrorCanBeIgnored() {
    Task {
        try await failWithExampleError()
    }
}

// Workaround:
// Handle the error inside the task, store the task, or explicitly discard it.

func workaround_task_handleInside() {
    Task {
        do throws(ExampleError) {
            let user = try await failWithExampleError()
            consume(user)
        } catch {
            print("Handled typed task failure:", error)
        }
    }
}

func workaround_task_storeHandle() async {
    let task = Task {
        try await failWithExampleError()
    }

    do {
        let user = try await task.value
        consume(user)
    } catch {
        print("Handled untyped Task failure:", error)
    }
}

// MARK: - 4. withCheckedThrowingContinuation cannot create typed continuations

// Problem:
// `CheckedContinuation<T, E>` is generic, but `withCheckedThrowingContinuation`
// currently hands you `CheckedContinuation<T, any Error>`, not
// `CheckedContinuation<T, ExampleError>`.
//
// Known status:
// - This has a Swift Forums thread from 2024.
// - A 2026 pre-pitch says typed throws plus nonisolated(nonsending) adoption
//   across continuation APIs is planned/in progress.
// - The released Swift 6.3.1 API still uses any Error.

/*
func broken_checkedThrowingContinuation() async throws(ExampleError) -> User {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<User, ExampleError>) in
        continuation.resume(throwing: .something)
    }
    // Swift 6.3.1:
    // error: cannot convert value of type '(CheckedContinuation<User, ExampleError>) -> ()'
    // to expected argument type '(CheckedContinuation<User, any Error>) -> Void'
}
*/

// Workaround:
// Use a non-throwing CheckedContinuation carrying Result<T, E>, then call get().
// This is the most solid current workaround because Result.get() is typed.

func withCheckedTypedThrowingContinuation<T, E: Error>(
    _ body: (TypedCheckedContinuation<T, E>) -> Void
) async throws(E) -> sending T {
    try await withCheckedContinuation { (rawContinuation: CheckedContinuation<Result<T, E>, Never>) in
        let continuation = TypedCheckedContinuation(rawContinuation: rawContinuation)
        body(continuation)
    }.get()
}

struct TypedCheckedContinuation<T, E: Error>: Sendable {
    private let rawContinuation: CheckedContinuation<Result<T, E>, Never>

    init(rawContinuation: CheckedContinuation<Result<T, E>, Never>) {
        self.rawContinuation = rawContinuation
    }

    func resume(returning value: sending T) {
        rawContinuation.resume(returning: .success(value))
    }

    func resume(throwing error: E) {
        rawContinuation.resume(returning: .failure(error))
    }

    func resume(with result: sending Result<T, E>) {
        switch result {
        case let .success(success):
            rawContinuation.resume(returning: .success(success))
        case let .failure(failure):
            rawContinuation.resume(returning: .failure(failure))
        }
    }

    func resume() where T == Void {
        rawContinuation.resume(returning: .success(()))
    }

    func resumeAwaiting(_ closure: @Sendable @escaping () async throws(E) -> T) {
        Task {
            do throws(E) {
                let value = try await closure()
                resume(returning: value)
            } catch {
                resume(throwing: error)
            }
        }
    }
}

extension CheckedContinuation {
    func resumeAwaiting(_ closure: @Sendable @escaping () async throws(E) -> T) {
        Task {
            do throws(E) {
                let value = try await closure()
                resume(returning: value)
            } catch {
                resume(throwing: error)
            }
        }
    }
}

func workaround_checkedTypedContinuation() async throws(ExampleError) -> User {
    try await withCheckedTypedThrowingContinuation { (continuation: TypedCheckedContinuation<User, ExampleError>) in
        continuation.resume(returning: User(id: 42))
    }
}

func workaround_checkedTypedContinuation_resumeAwaiting() async throws(ExampleError) -> User {
    try await withCheckedTypedThrowingContinuation { (continuation: TypedCheckedContinuation<User, ExampleError>) in
        continuation.resumeAwaiting { () async throws(ExampleError) in
            try await failWithExampleError()
        }
    }
}

// MARK: - 5. Closure typed throws inference is incomplete

// Problem:
// A closure assigned to a typed-throwing function type does not infer its
// thrown type from context in many places. It defaults to `any Error`.
//
// Known status:
// - SE-0413 says the original FullTypedThrows inference work was not completed
//   for Swift 6.0 and moved to future directions.
// - Related issues and forum threads remain open/active.

/*
let brokenClosure1: () async throws(ExampleError) -> Void = {
    throw .something
    // Swift 6.3.1:
    // error: type 'any Error' has no member 'something'
}

let brokenClosure2: () async throws(ExampleError) -> Void = {
    throw ExampleError.something
    // Swift 6.3.1:
    // error: thrown expression type 'any Error' cannot be converted to error type 'ExampleError'
}
*/

// Workaround:
// Repeat the closure signature explicitly. This is noisy but reliable.

let workaroundClosure: () async throws(ExampleError) -> Void = {
    () async throws(ExampleError) in
    throw .something
}

// A shorter form sometimes works when the expected type is already strong
// enough and the compiler can infer the concrete thrown type placeholder.

/*
let workaroundClosureInferredPlaceholder: () async throws(ExampleError) -> Void = {
    () async throws(_) in
    throw .something
}
// Some forum examples use `throws(_)` successfully in narrower contexts, but
// this top-level assignment still fails in Swift 6.3.1:
// error: type placeholder not allowed here
*/

// MARK: - 6. do-catch often exposes any Error unless do throws(E) is explicit

// Problem:
// In closure contexts, a plain catch often binds `error` as any Error even when
// the do block only calls a single `throws(ExampleError)` function.

/*
let brokenDoCatchInClosure: () async -> Void = {
    do {
        _ = try await failWithExampleError()
    } catch {
        let typed: ExampleError = error
        // Swift 6.3.1:
        // error: cannot convert value of type 'any Error' to specified type 'ExampleError'
        print(typed)
    }
}
*/

// Workaround:
// Give the do statement its thrown type explicitly.

let workaroundDoCatchInClosure: () async -> Void = {
    do throws(ExampleError) {
        _ = try await failWithExampleError()
    } catch {
        let typed: ExampleError = error
        print("Typed catch:", typed)
    }
}

// MARK: - 7. Exhaustive catch over a typed error enum is not recognized

// Problem:
// The compiler can still fail to recognize that enum-pattern catch clauses are
// exhaustive for a typed thrown error.
//
// Known status:
// - Open Swift issue #74555.

/*
func broken_exhaustiveCatchIsNotRecognized() {
    do {
        _ = try failSynchronously()
    } catch ExampleError.something {
    } catch ExampleError.cancelled {
    } catch ExampleError.network {
    } catch ExampleError.decoding {
    } catch ExampleError.wrapped(_) {
    }
    // Swift issue #74555 shows the simpler shape with enum cases .a and .b.
    // The compiler says errors thrown from the do block are not handled because
    // the enclosing catch is not exhaustive.
}
*/

func failSynchronously() throws(ExampleError) -> User {
    throw .something
}

// Workaround:
// Catch once, then switch over the typed error. This gets normal switch
// exhaustiveness checking.

func workaround_exhaustiveSwitchInCatch() {
    do {
        _ = try failSynchronously()
    } catch {
        switch error {
        case .something:
            print("something")
        case .cancelled:
            print("cancelled")
        case .network:
            print("network")
        case .decoding:
            print("decoding")
        case .wrapped(let underlying):
            print("wrapped", underlying)
        }
    }
}

// MARK: - 8. Multiple concrete error types collapse to any Error

// Problem:
// Swift has one thrown error type per function. There is no spelling like:
//
//     throws(ExampleError | OtherExampleError)
//
// SE-0413 explicitly did not accept multiple thrown error types. Anonymous
// union/sum types are a future direction, not an accepted feature.

/*
func broken_multipleErrorTypes() throws(ExampleError) -> User {
    do {
        if Bool.random() {
            return try failSynchronously()
        } else {
            return try decodeUser()
        }
    } catch {
        throw error
        // `error` is any Error when different concrete thrown types meet.
    }
}
*/

// Workaround A:
// Model the union explicitly as a domain enum.

enum LoadUserError: Error {
    case example(ExampleError)
    case other(OtherExampleError)
}

func workaround_multipleErrors_domainEnum() throws(LoadUserError) -> User {
    do throws(ExampleError) {
        return try failSynchronously()
    } catch {
        throw .example(error)
    }
}

func workaround_multipleErrors_wrapBothBranches(useOther: Bool) throws(LoadUserError) -> User {
    if useOther {
        do throws(OtherExampleError) {
            return try decodeUser()
        } catch {
            throw .other(error)
        }
    } else {
        do throws(ExampleError) {
            return try failSynchronously()
        } catch {
            throw .example(error)
        }
    }
}

// Workaround B:
// An Either-style helper can be useful for internal plumbing, but domain enums
// usually read better at module boundaries.

enum EitherError<Left: Error, Right: Error>: Error {
    case left(Left)
    case right(Right)
}

func workaround_multipleErrors_either(useOther: Bool) throws(EitherError<ExampleError, OtherExampleError>) -> User {
    if useOther {
        do throws(OtherExampleError) {
            return try decodeUser()
        } catch {
            throw .right(error)
        }
    } else {
        do throws(ExampleError) {
            return try failSynchronously()
        } catch {
            throw .left(error)
        }
    }
}

// MARK: - 9. withThrowingTaskGroup uses any Error

// Problem:
// Task groups are one of the most natural concurrency APIs, but the current
// throwing group surface still exposes `any Error` in released toolchains.
// Passing a typed-throwing operation through a throwing task group can lose the
// specific thrown type.
//
// Related status:
// - The 2023 "Typed throws in the Concurrency module" pitch covered task groups.
// - 2026 forum posts say typed throws adoption across Concurrency APIs is
//   actively being worked through, but ABI/source compatibility makes it hard.

/*
func broken_taskGroup_erasesTypedError() async throws(ExampleError) -> User {
    try await withThrowingTaskGroup(of: User.self) { group in
        group.addTask {
            try await failWithExampleError()
        }

        return try await group.next()!
    }
    // Depending on the exact spelling, Swift 6.3.1 reports an `any Error`
    // crossing the `throws(ExampleError)` boundary.
}
*/

// Workaround:
// Use a non-throwing task group whose result value is Result<Success, Failure>.

func workaround_taskGroup_resultTunnel() async throws(ExampleError) -> [User] {
    await withTaskGroup(of: Result<User, ExampleError>.self) { group in
        for _ in 0..<3 {
            group.addTask {
                await asyncResult { () async throws(ExampleError) in
                    try await fetchUser()
                }
            }
        }

        var users: [User] = []

        for await result in group {
            do {
                users.append(try result.get())
            } catch {
                print("A child failed with typed error:", error)
            }
        }

        return users
    }
}

// Alternative:
// If any failure should cancel the entire group, keep withThrowingTaskGroup and
// map the error at the outer boundary.

func workaround_taskGroup_forceError() async throws(ExampleError) -> User {
    try await forceError(ExampleError.self) {
        try await withThrowingTaskGroup(of: User.self) { group in
            group.addTask {
                try await failWithExampleError()
            }

            guard let user = try await group.next() else {
                throw ExampleError.something
            }

            group.cancelAll()
            return user
        }
    }
}

// MARK: - 10. CancellationError does not fit typed domain errors automatically

// Problem:
// `Task.checkCancellation()` throws CancellationError. A function declared as
// `throws(ExampleError)` cannot throw that directly.
//
// This is not just a compiler limitation. It is an API design question:
// should cancellation be a domain failure, or a control-flow signal?

/*
func broken_cancellationInTypedFunction() async throws(ExampleError) {
    try Task.checkCancellation()
    // Swift 6.3.1:
    // error: thrown expression type 'CancellationError' cannot be converted
    // to error type 'ExampleError'
}
*/

// Workaround A:
// Map cancellation into your domain.

func workaround_cancellation_mapToDomain() async throws(ExampleError) {
    do {
        try Task.checkCancellation()
    } catch is CancellationError {
        throw .cancelled
    } catch {
        throw .wrapped(error)
    }
}

// Workaround B:
// Use the non-throwing check if you want to keep the typed error surface clean.

func workaround_cancellation_isCancelled() async throws(ExampleError) {
    guard !Task.isCancelled else {
        throw .cancelled
    }
}

// MARK: - 11. Result.get() as a typed error tunnel

// Observation:
// `Result<Success, Failure>.get()` is one of the most useful existing tools
// for preserving a typed failure across APIs that erase thrown errors.

func resultTunnel<T, E: Error>(
    _ operation: () async throws(E) -> T
) async -> Result<T, E> {
    await asyncResult(operation)
}

func example_resultTunnel() async throws(ExampleError) -> User {
    let result: Result<User, ExampleError> = await resultTunnel { () async throws(ExampleError) in
        try await failWithExampleError()
    }

    return try result.get()
}

// MARK: - 12. sending / Sendable and typed errors

// Problem space:
// Modern Concurrency APIs increasingly use `sending` and `@Sendable` to model
// values and closures crossing task or actor boundaries. This is orthogonal to
// typed throws, but the two features meet at Task, task groups, continuations,
// and async streams.
//
// Open questions to keep checking:
// - If an error crosses a task boundary, should the concrete Failure type be
//   Sendable?
// - Should helper wrappers require `Failure: Sendable`, even if Swift's
//   `Task<Success, Failure>` only says `Failure: Error`?
// - How should `sending T` be used in continuation wrappers to match current
//   standard library conventions?
//
// Conservative helper design:
// - Keep operation closures `@Sendable`.
// - Require `Success: Sendable` in wrappers that spawn tasks.
// - Consider `Failure: Error & Sendable` in application helpers when errors
//   are passed between tasks.

struct StrictTypedTask<Success: Sendable, Failure: Error & Sendable>: Sendable {
    private let task: Task<Result<Success, Failure>, Never>

    init(operation: @Sendable @escaping () async throws(Failure) -> Success) {
        task = Task {
            await asyncResult { () async throws(Failure) in
                try await operation()
            }
        }
    }

    var value: Success {
        get async throws(Failure) {
            try await task.value.get()
        }
    }
}

// MARK: - Shared Types

enum ExampleError: Error, Sendable {
    case something
    case cancelled
    case network
    case decoding
    case wrapped(any Error & Sendable)
}

enum OtherExampleError: Error {
    case other
}

struct User: Sendable, Equatable {
    let id: Int
}

func fetchUser() async throws(ExampleError) -> User {
    User(id: 1)
}

func failWithExampleError() async throws(ExampleError) -> User {
    throw .something
}

func decodeUser() throws(OtherExampleError) -> User {
    throw .other
}

func consume(_ user: User) {
    print(user)
}

// MARK: - Shared Workaround Helpers

func asyncResult<Success, Failure: Error>(
    _ operation: () async throws(Failure) -> Success
) async -> Result<Success, Failure> {
    do throws(Failure) {
        return try await .success(operation())
    } catch {
        return .failure(error)
    }
}

// Force an untyped throwing async operation back into a typed error.
//
// This is useful as a narrow adapter around APIs that are known to throw only E
// but whose signatures still say `any Error`.
//
// Warning:
// This intentionally traps if the body throws a different error type. Prefer a
// real mapping function when the boundary can throw several error domains.

func forceError<Success, Failure: Error>(
    _: Failure.Type,
    _ body: () async throws -> Success
) async throws(Failure) -> Success {
    do {
        return try await body()
    } catch {
        throw error as! Failure
    }
}

func mapError<Success, Failure: Error>(
    _ body: () async throws -> Success,
    transform: (any Error) -> Failure
) async throws(Failure) -> Success {
    do {
        return try await body()
    } catch {
        throw transform(error)
    }
}
