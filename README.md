<p align="center">
  <img src="typed-error-throwing-fixes/assets/typed-error-throwing-fixes_circle.png" alt="Typed Error Throwing Fixes" width="140">
</p>

<h1 align="center">Typed Error Throwing Fixes</h1>

<p align="center">
  <img alt="AI Agents - Skill" src="https://img.shields.io/badge/AI--Agents-Skill-EF9035?style=flat">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-blue?style=flat"></a>
  <a href="https://www.linkedin.com/in/wolfgang-muhsal-12408194/"><img alt="LinkedIn" src="https://img.shields.io/badge/Contact-LinkedIn-95a5a6.svg?style=flat"></a>
</p>

Typed Error Throwing Fixes is an agent skill for Codex and other AI coding assistants that helps review and repair Swift 6 typed-throws code.

It is useful when Swift's typed `throws(E)` model meets current compiler and concurrency edge cases, including `async let`, `Task`, continuations, task groups, cancellation, typed closures, `do throws(E)`, and `Result`-based error tunnels.

## Installing Typed Error Throwing Fixes

Install the skill with `npx`:

```bash
npx skills add https://github.com/Gucky/TypedErrorThrowingFixes --skill typed-error-throwing-fixes
```

To install it globally for Codex:

```bash
npx skills add https://github.com/Gucky/TypedErrorThrowingFixes --skill typed-error-throwing-fixes --agent codex --global
```

For a specific agent:

```bash
npx skills add https://github.com/Gucky/TypedErrorThrowingFixes --skill typed-error-throwing-fixes --agent claude-code
```

For all supported agents:

```bash
npx skills add https://github.com/Gucky/TypedErrorThrowingFixes --skill typed-error-throwing-fixes --agent '*'
```

If `npx` is not available, install Node.js first. On macOS with Homebrew:

```bash
brew install node
```

## Using Typed Error Throwing Fixes

In Codex, trigger the skill directly:

```text
$typed-error-throwing-fixes
```

You can also ask naturally:

```text
Use the Typed Error Throwing Fixes skill to review this Swift typed-throws code.
```

The skill helps with:

- Preserving concrete thrown error types across Swift Concurrency boundaries.
- Replacing accidental `any Error` widening with typed `Result` tunnels or explicit mapping.
- Handling current rough edges in `async let`, `Task`, continuations, and task groups.
- Writing explicit typed-throwing closure signatures when inference falls short.
- Treating cancellation deliberately inside typed domain error APIs.

## Safety Model

This skill is guidance and reference material for Swift code changes. It does not run project-specific migrations on its own. When used to modify a codebase, validate with the active Swift toolchain because typed-throws diagnostics can depend on the compiler version.

## Requirements

- Swift 6 typed-throws code or review context
- Node.js for `npx`
- An AI coding assistant that supports agent skills

## License

Typed Error Throwing Fixes was created by [Wolfgang Muhsal](https://github.com/Gucky). It is available under the [MIT License](LICENSE), which permits commercial use, modification, distribution, and private use.
