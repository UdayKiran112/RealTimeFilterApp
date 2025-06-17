# 🎥 RealTime Filter App

A real-time iOS camera filter application built with **Swift**, **Metal**, and **MTKView**, supporting custom GPU-accelerated shaders for dynamic image processing. This app allows users to apply a variety of visual effects including color filters, vertex warp effects, and compute-based transformations like Gaussian blur and edge detection.

## 🚀 Features

- 📸 **Real-time camera feed rendering**
- 🎨 **Multiple color filters** (grayscale, sepia, invert, brightness, contrast)
- 🌊 **Vertex warp effects** (magnifier, sine wave distortion)
- 🔍 **Advanced fragment shader effects** (chromatic aberration, tone mapping, vignette, grain)
- ⚙️ **Compute shader filters**:
  - Gaussian blur
  - Sobel edge detection
- 🧠 **Modular shader design** in `shaders.metal`
- 🧼 Optimized GPU performance using Metal API
- 🖼️ Clean UI for selecting and applying filters

## 📁 Project Structure

```bash
RealTimeFilterApp/
├── RealTimeFilterApp/          # Main Swift source files
│   ├── AppDelegate.swift
│   ├── ViewController.swift
│   ├── Renderer.swift          # Metal rendering logic
│   └── CameraManager.swift     # AVCapture setup and management
├── Shaders/
│   └── shaders.metal           # Unified Metal shader file
├── Assets.xcassets             # App icons and assets
├── Info.plist
└── README.md

```

## 🛠️ Requirements

- Xcode 15+
- iOS 15.0+
- Swift 5.7+
- Metal-compatible iOS device

## 📲 iOS – Real-Time Filter App: Setup Instructions

1. Open the project in Xcode:

   ```bash
   cd iOS_Assg/RealTimeFilterApp/
   open RealTimeFilterApp.xcodeproj
   ```

2. Connect an iOS device (iPhone/iPad)

3. In Xcode:

   - Select your connected device as the build target
   - Trust the developer certificate on your iPhone if prompted

4. Press **Run** (▶️) or use `Cmd + R` to build and deploy the app to your device

> **Note:** This app uses **Metal shaders** for real-time filtering. Ensure your device supports Metal and camera access is granted.

## 🧪 How It Works

1. Captures real-time camera frames using `AVCaptureSession`
2. Converts frames to `MTLTexture` format
3. Applies selected filter pipeline via Metal shaders:

   - **Vertex Shader** for spatial warping
   - **Fragment Shader** for color effects
   - **Compute Shader** for post-processing

4. Displays the final output using `MTKView`

## 📸 Demo

> 📌 _Add screenshots or a video here if available_

## 🧩 Shader Modes (in `shaders.metal`)

- **Color Filters**: Select using `filterIndex`
- **Vertex Warp Modes**: Controlled by `warpMode`
- **Fragment Effects**: Combined in main shader logic
- **Compute Pass**: For intensive processing (e.g., Gaussian, Sobel)

## ✍️ Author

**Gedela Uday Kiran**
📧 [udaykiranuk1126@gmail.com](mailto:udaykiranuk1126@gmail.com)
🔗 [LinkedIn](https://www.linkedin.com/in/uday-kiran-gedela) | [GitHub](https://github.com/UdayKiran112)

---
