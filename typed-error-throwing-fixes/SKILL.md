---
name: typed-error-throwing-fixes
description: Swift 6 typed throws troubleshooting and fixes. Use when writing, reviewing, or repairing Swift code that uses `throws(E)` / `async throws(E)`, especially with closure inference, `async let`, `Task`, task groups, continuations, cancellation, `Result.get()` tunnels, and `Sendable`/`sending` concurrency boundaries.
---

# Typed Error Throwing Fixes

Use this skill to keep Swift typed-throws code compiling and intentionally typed across common Swift 6 / Swift Concurrency edge cases.

## Workflow

1. Prefer preserving the concrete thrown error type with explicit `throws(E)` annotations, typed `Result<T, E>` tunnels, or explicit error mapping.
2. Use `references/typed-error-throwing-improvements.swift` as the primary reference. Read or grep it when you need examples, statuses, workarounds, or source links. It documents:
   - `async let` widening to `any Error`, including tuple await such as `try await (a, b, c)`.
   - `Task {}` erasing typed thrown errors and discarded throwing task behavior / SE-0520.
   - `withCheckedThrowingContinuation` and typed continuation wrappers using `Result<T, E>`.
   - Closure typed-throws inference failures and required boilerplate.
   - `do throws(E)` and `catch` behavior.
   - Missing union types / multiple concrete error domains.
   - `withThrowingTaskGroup` typed error limitations.
   - `CancellationError` inside typed domain APIs.
   - `Result.get()` as a typed error tunnel.
   - `sending` / `Sendable` considerations around typed thrown errors.
3. Do not use force-cast error adapters such as `as! E` as serious production fixes to solve typed throws; treat them only as last-resort demonstrations of compiler limitations.
4. Highlight this fix pattern as especially important: for typed-throwing closures, write the closure signature explicitly when needed. See `references/typed-error-throwing-improvements.swift`, section `5. Closure typed throws inference is incomplete`.

```swift
{ () async throws(MyError) in
    throw .something
}
```

5. When changing code, verify with the active project toolchain. Many failures appear as `any Error` inference even when the surrounding API looks typed.
