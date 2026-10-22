# 💸 SplitEase — Smart F&B Receipt Scanner & Bill Splitting App

**SplitEase** is a cross-platform Flutter application designed to make splitting restaurant and café bills effortless, accurate, and fair across **Malaysia** and **Singapore**.

Powered by **Google ML Kit OCR**, **Firebase Cloud Functions**, and deterministic exact-cent financial math, SplitEase handles complex F&B receipt structures—including English, Malay, and Chinese text, discounts, service charges, SST/GST taxes, rounding adjustments, and multi-currency conversions.

---

## 📲 Download the App (Bundled APK)

You can download and test the pre-compiled Android APK directly from the repository:

👉 **[Download SplitEase Android APK (releases/splitease-app.apk)](releases/splitease-app.apk)**

### Installation Instructions
1. Download `splitease-app.apk` on your Android device.
2. Tap the downloaded file to install. (Enable *"Install from Unknown Sources"* in your browser settings if prompted).
3. Open SplitEase, sign in via **Google Sign-In** or **Email**, and start scanning bills!

---

## 🌟 Key Features

### 🧾 1. Multi-Language F&B OCR Receipt Scanning
* **Trilingual OCR**: Uses Google ML Kit with Chinese and Latin script recognition to parse English, Malay, and Chinese character dishes (e.g. `肉碎蛋酒面线汤`, `咸蛋虾仁烩饭`, `红糖桂圆凉茶`).
* **Smart Structure Recognition**: Automatically detects merchants, item unit prices, quantities, subtotal, SST (6% MY) / GST (9% SG), 10% Service Charge, item discounts, and rounding adjustments.
* **Header & Summary Filter**: Intelligently ignores duplicate POS `Charges summary` footer blocks to prevent double-counting taxes.

### 🧮 2. Proportional Tax & Service Charge Math
* **Separate Charges**: Keeps Tax (SST/GST) and Service Charge strictly separated.
* **Food-Weighted Allocation**: Tax and Service Charge are allocated proportionally to each participant based on the value of food they ate using `Money.allocate()` (largest-remainder method).
* **Exact-Cent Matching**: Guaranteed zero rounding loss; sum of participant shares matches the printed venue receipt total down to the exact cent.
* **Arithmetic Reconciliation**: Calculates printed total vs sum of line items. Displays a `⚠️ Reconciliation Warning` if an unexplained receipt discrepancy exists.

### 👥 3. Participant-First Flow & Dish Assignment
* Add participants sharing the bill first, then assign dishes with interactive filter chips.
* **Equal Split Default**: Unassigned items or equal split policies automatically divide the total evenly across all participants (`MYR 173.90` / 2 = `MYR 86.95` each).

### 🔔 4. Interactive Notification Workflow
* Tapping **Notify Unpaid Participants** opens a participant selector sheet.
* Select specific unpaid participants before queueing and sending payment reminders.
* Triggers Firebase Cloud Functions (v2) to deliver push notifications (FCM) and itemized HTML email breakdowns via Nodemailer.

### 🌐 5. Multi-Currency & Dark Mode Brand UI
* Supports MYR, SGD, USD, EUR, GBP, JPY, and real-time exchange rate snapshot conversion.
* High-contrast dark theme styled with Electric Blue (`#1B6EF3`), Mint Teal (`#00C897`), and Gold Amber (`#FFB800`).

---

## 🚀 Future Roadmap: Third-Party WhatsApp API Integration

In upcoming updates, SplitEase will integrate with **Third-Party WhatsApp Cloud API** (Meta WhatsApp Business API / Twilio) to replace and complement email reminders:

* 💬 **Instant WhatsApp Payment Reminders**: Send formatted payment reminders directly to participants' WhatsApp numbers with a single tap.
* 📋 **Rich Itemized WhatsApp Breakdowns**: Deliver clean, formatted WhatsApp text templates detailing exactly which dishes each participant ordered, their proportional tax/service charge share, and payment details.
* 🔗 **1-Tap Payment Links**: Include direct Touch 'n Go eWallet, DuitNow QR, or PayNow links directly inside the WhatsApp reminder message.

---

## 🛠️ Tech Stack & Architecture

* **Framework**: Flutter 3 (Dart 3)
* **State Management**: Flutter Riverpod 2.6
* **Backend**: Firebase Auth, Cloud Firestore, Firebase Messaging (FCM)
* **Serverless Backend**: Firebase Cloud Functions v2 (Node.js 22 + Nodemailer)
* **On-Device OCR**: Google ML Kit Text Recognition (`script: TextRecognitionScript.chinese`)
* **Utilities**: `url_launcher`, `intl`, `http`

---

## 💻 Developer Setup Guide

### 1. Prerequisites
* Flutter SDK (3.24 or higher)
* Android Studio / Xcode
* Node.js 22 (for Cloud Functions)
* Firebase CLI (`npm install -g firebase-tools`)

### 2. Running Locally
```bash
git clone https://github.com/Taylorchong123/splitease.git
cd splitease
flutter pub get
flutter run
```

### 3. Running Unit Tests & Static Analysis
```bash
flutter test
flutter analyze
```

### 4. Firebase Cloud Functions Setup
1. Create `functions/.env`:
   ```env
   EMAIL_SERVICE=gmail
   EMAIL_USER=your-email@gmail.com
   EMAIL_PASS=your-16-digit-app-password
   ```
2. Deploy Cloud Functions:
   ```bash
   firebase deploy --only functions
   ```

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
