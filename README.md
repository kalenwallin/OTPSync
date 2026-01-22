[![Clipsync logo](mac/ClipSync/Assets.xcassets/AppIcon.appiconset/Readme-logo.png)]

#  ClipSync: Seamless Universal Clipboard

**ClipSync** is the ultimate tool to synchronize your clipboard across all your devices—**instantly** and **securely**. Copy on your Mac, paste on your Android. It's that simple. 🚀

> ✨ **Open Source, Secure, and Blazing Fast.**

---

## 🔥 Features

*   **⚡️ Instant Sync**: Copy text on one device and it’s immediately available on the other.
*   **🔒 End-to-End Encryption**: Your data is encrypted locally before it leaves your device. No prying eyes.
*   **📱 Cross-Platform**: Seamlessly works between **macOS** and **Android**.
*   **🔋 Efficient**: Optimized for minimal battery drain and background usage.
*   **🎨 Stunning UI**: Beautiful, native designs for both platforms.

---

## 🛠 Tech Stack

### 🍏 macOS App
*   **Language**: Swift 5.9
*   **Framework**: SwiftUI & AppKit
*   **Architecture**: MVVM
*   **Dependencies**: Firebase, Lottie

### 🤖 Android App
*   **Language**: Kotlin
*   **Framework**: Jetpack Compose, Material 3
*   **Architecture**: MVVM / Clean Architecture
*   **Dependencies**: Firebase, Coroutines, Hilt

---

## 🚀 Getting Started

To keep things organized, this repository contains both client applications.

### 🍏 macOS Setup

1.  Navigate to the Mac folder:
    ```bash
    cd ios-app # or whatever you named the folder
    ```
2.  **Secrets**: Download `GoogleService-Info.plist` from your Firebase Console and place it in the `ClipSync/` root.
3.  **Run**: Open `ClipSync.xcodeproj` (or `.xcworkspace`) in Xcode 15+ and run.

### 🤖 Android Setup

1.  Navigate to the Android folder:
    ```bash
    cd android-app
    ```
2.  **Secrets**:
    *   Download `google-services.json` from Firebase and place it in `app/`.
    *   Ensure any `local.properties` values are set if required.
3.  **Run**: Open the project in Android Studio Iguana+ and run on your device/emulator.

---

## 🛡 Security & Secrets

**Use your own keys!**
This project uses Firebase. For security reasons, our config files (`google-services.json` and `GoogleService-Info.plist`) are **NOT** included in the repository.

*   **Contributors**: You must create your own free Firebase project to build and test the app.
*   **Encryption**: If you are deploying this for personal use, verify that you are using a secure, unique encryption key so only your devices can read the clipboard data.

---

## 🤝 Contributing

We love contributions!
1.  **Fork** the project.
2.  Create your **Feature Branch**.
3.  **Commit** your changes.
4.  **Push** to the branch.
5.  Open a **Pull Request**.

---

## 📜 License

Distributed under the **MIT License**. See `LICENSE` for more information.
