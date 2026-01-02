# PageTMB intent!

This app is meant to be a first-draft word processor for authors writing Manuscripts, Collage Essays, or Screenplays.  These people have rigid requirements for margins, pagination, fonts, text layout and supported file formats (namely .docx and .pdf).  We need to make sure we provide solutions for all these requirements.

There should also be a freestyle mode for writing pretty much anything else.  This will be our default mode.

I'd like for this app to be multi-platform, and cross-device.  I'd like for this app to be able to run on Windows, Linux, and macOS.  I'd like for this app to be able to run on mobile devices as well.

## Features
- Default fonts
    - Screenplay (Courier Prime, 12pt)
    - Manuscript (Tinos, 12pt)
    - Essay (Tinos, 12pt)
    - Freestyle should be able to use any font available in the app (we will not support system fonts).
    - We need to support various screen resolutions and DPIs. Be sure things are DPI-aware.
    - We need to support Spell Checking.
    - We need to support Undo and Redo.
    - We need to support Cut, Copy, and Paste.
    - We need to support Find and Replace.
    - We need to support Find Next and Find Previous.
    - We need to support Find All.
### Text Layout
- Text should be left aligned by default
- Text should be double spaced in manuscript mode and Essay mode
- Text should be paginated (8.5" x 11" for US)
- We need to support centered text and right aligned text as well
- This will be a rich text editor, so we need to support bold, italic, underline, and strikethrough at a minimum. Because we will support markdown file importing, we should support as many rich text features of markdown as pragmatically possible.
### File formats
- Save to it's own format with an extension of .ptmb that doesn't conflict with other file formats
- support for exporting to .docx and .pdf 
- support for importing from .txt and .md (markdown) as well as it's own native format

### Document Layout
- Fixed page size (8.5" x 11" for US)
    - Margins for Screenplay (1" top, 1" bottom, 1.5" left, 1" right)
    - Margins for Manuscript (1" top, 1" bottom, 1" left, 1" right)
    - Margins for Essay (1" top, 1" bottom, 1" left, 1" right)
    - Margins for Freestyle (1" top, 1" bottom, 1" left, 1" right)
