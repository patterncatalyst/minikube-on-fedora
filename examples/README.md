# examples/

Runnable code that the tutorial references. **Not** included in the
published Jekyll site (excluded via `_config.yml`).

## Convention

Each example is a directory under `examples/`:

```
examples/
├── README.md             ← this file
├── hello-world/
│   ├── Containerfile
│   ├── README.md         ← what this example demonstrates
│   └── (source code)
└── another-example/
    └── ...
```

Each `examples/<name>/README.md` should explain:

- What this example demonstrates
- How it relates to a tutorial section (e.g., "companion to §4")
- How to build and run it (one or two commands)
- Expected output

## Test script pairing

For every `examples/<name>/`, there should be a
`scripts/test-<name>.sh` that builds, runs, and validates the
example end-to-end. See `scripts/test-template.sh` for the starting
point.

Once you have multiple examples, add a `scripts/test-all-examples.sh`
aggregator that runs them all.

## Why examples are separate from tutorial prose

The tutorial's Containerfiles, when rendered as code blocks, are for
the reader to copy and paste. The runnable version under
`examples/` is what you actually test against — same file, different
purpose.

Keeping them separate lets you:

- Test the example end-to-end without re-extracting code from
  Markdown
- Update the example without dragging through the prose
- Share the example as a standalone artifact (anyone can clone the
  repo and `podman build examples/foo/`)
