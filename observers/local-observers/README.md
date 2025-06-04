# Local Observers

This is a simplified version of the observers system that runs locally without external extensions like Glean.

## How it works

1. **Screenshots**: Takes screenshots every 20 seconds and stores them in `/tmp/screenshots`

2. **Image Description**: Every 20 minutes:
   - Uses `ollama run llava` to describe each screenshot
   - Saves descriptions to `/tmp/screenshot-descriptions/`
   - Removes the original screenshots to save space

3. **Work Analysis**: After describing images, runs `recipe-work-simple.yaml` which:
   - Analyzes the text descriptions instead of images
   - Updates work summaries in `~/.local/share/goose-perception/WORK.md`

4. **Other Recipes**: Runs 3 additional simplified recipes on schedule:
   - `recipe-focus-simple.yaml` (hourly) - Focus and productivity analysis
   - `recipe-contributions-simple.yaml` (daily) - Git and file activity analysis  
   - `recipe-interactions-simple.yaml` (daily) - Communication and interaction analysis

## Requirements

- `ollama` installed with the `llava` model
- `goose` CLI tool
- macOS (for `screencapture` command)

## Usage

```bash
cd observers/local-observers
./run-local-observations.sh
```

## Key Differences from Main Observers

- No Glean extension usage
- Uses ollama/llava for image description instead of direct image analysis
- Only 4 recipes instead of 15+
- Simplified logic and dependencies
- Text-based analysis instead of image-based

## Files

- `run-local-observations.sh` - Main script
- `recipe-work-simple.yaml` - Work analysis from text descriptions
- `recipe-focus-simple.yaml` - Focus and productivity analysis
- `recipe-contributions-simple.yaml` - Local git and file activity analysis
- `recipe-interactions-simple.yaml` - Communication analysis from available data