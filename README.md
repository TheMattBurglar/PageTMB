# PageTMB

**PageTMB** is a specialized word processor designed for writers of screenplays, manuscripts, essays, and creative prose. It prioritizes layout fidelity, distraction-free writing, and seamless multi-platform support (Desktop & Android).

## Key Features

### 🖋️ Specialized Writing Modes
PageTMB adapts its layout, typography, and pagination to match industry standards for various formats:
*   **Screenplay**: Industry-standard margins, Courier Prime font, and automatic scene/character alignment helpers.
*   **Manuscript**: Standard fiction/non-fiction submission formatting (Times New Roman equivalent - Tinos, double-spaced).
*   **Essay**: Academic-ready formatting with precise line spacing and margins.
*   **Freestyle**: A clean slate for anything else, with flexible styling options.

### 📄 Professional Export & Print
*   **High-Fidelity PDF**: Pixel-perfect PDF generation that preserves every margin and font detail.
*   **DOCX Export**: Compatible with Microsoft Word, including full support for styles and layout metadata.
*   **Native Printing**: Print directly from the app with correct pagination and scaling.

### 🛠️ Advanced Editor Tools
*   **Real-time Pagination**: See exactly how your document will look on the printed page as you type.
*   **Persistent MetaData**: Save author, title, and versioning info directly in the `.ptmb` file.
*   **Find & Replace**: Sophisticated search tools with "Find All" and "Replace All" capabilities.
*   **Spell Check**: Integrated spell-checking to keep your drafts clean.
*   **Markdown Support**: Import and export standard Markdown files for cross-tool compatibility.

### 📱 Mobile-First Optimizations
Fully optimized for Android and mobile devices:
*   **Soft Keyboard Integration**: Custom `TextInputClient` bridge for smooth, native-feeling typing on mobile.
*   **Responsive Toolbar**: Horizontally scrollable toolbar that puts all your tools within thumb's reach on any screen size.
*   **Touch-Optimized**: Precise caret placement and word selection tailored for touch interaction.

## Getting Started

### Prerequisites
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) (Stable)
*   Android Studio / VS Code (for development)

### Running the App
```bash
# Get dependencies
flutter pub get

# Run on your default device
flutter run
```

### Building for Release
```bash
# Android
flutter build apk --release

# Windows
flutter build windows

# Linux
flutter build linux
```

## File Formats
*   `.ptmb`: Native JSON-based format that preserves all rich text and document metadata.
*   `.md`: Standard Markdown import/export.
*   `.txt`: Plain text support.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---
*Created for writers, by writers.*
