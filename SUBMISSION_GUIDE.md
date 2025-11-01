# How to Create Submission ZIP

## What to Include in project4.zip

```bash
# From the project root directory, create the zip:
zip -r project4.zip \
  src/ \
  test/ \
  gleam.toml \
  manifest.toml \
  PROJECT_README.md \
  REPORT.md \
  -x "*/build/*" "*/.*"
```

## Or manually include these files:

```
project4/
├── src/
│   ├── dosp_project_4_part1.gleam  # Main entry point
│   ├── engine.gleam                # Engine actor
│   ├── simulator.gleam             # Simulator
│   └── types.gleam                 # Data types
├── test/
│   └── dosp_project_4_part1_test.gleam  # Tests
├── gleam.toml                      # Dependencies
├── manifest.toml                   # Lock file
├── PROJECT_README.md               # How to run
└── REPORT.md                       # Detailed report
```

## Do NOT include:
- `build/` directory (generated files)
- `.git/` directory
- Hidden files
- Binary files

## How Grader Will Run

```sh
# Extract zip
unzip project4.zip
cd project4/

# Download dependencies (requires internet)
gleam deps download

# Build
gleam build

# Run simulation
gleam run

# Run tests
gleam test
```

## Report PDF
Submit `REPORT.md` content as PDF separately on Canvas (not in zip).

## Team Member Info
Add in Canvas comment field:
- Member 1 Name & UFID
- Member 2 Name & UFID
