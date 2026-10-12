<div align="center">

# 💸 SplitEase

**Scan a bill, add your friends, assign dishes, split fairly, and notify everyone with an itemized breakdown.**

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=flat-square&logo=dart&logoColor=white)](https://dart.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-Auth%20%7C%20Firestore%20%7C%20FCM-FFCA28?style=flat-square&logo=firebase&logoColor=black)](https://firebase.google.com/)

</div>

---

## 📖 Table of Contents

- [About](#-about)
- [Features](#-features)
- [Tech Stack](#-tech-stack)
- [Architecture](#-architecture)
- [Project Structure](#-project-structure)
- [Getting Started](#-getting-started)
- [Data Model](#-data-model)
- [Testing](#-testing)
- [Roadmap](#-roadmap)
- [License](#-license)

---

## 🎯 About

Splitting a bill after a group dinner, a trip, a grocery run, or a utility invoice is awkward: someone pays up front, someone forgets, and the chasing begins.

**SplitEase** is a modern cross-platform Flutter app. Snap a photo of any physical bill or key it in manually, add participants, assign individual dishes/items to specific people, calculate proportional tax and totals, and send push notifications and itemized email reminders. Every bill is tracked as a **ticket** with status updates from draft to settled.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔐 **User Authentication** | Email/password and **Google Sign-In**, both via Firebase Auth. |
| 🧾 **OCR Bill Scanning** | On-device OCR (Google ML Kit) reads items, quantities, prices, tax, and totals from a photo. |
| 👥 **Add Participants First** | Invite friends by name and email before assigning items. |
| 🍕 **Individual Food Assignment** | Assign individual dishes to specific participants using interactive chips, or split equally among everyone. |
| 🌍 **Multi-Currency** | Each bill has its own currency with live rate snapshots. |
| 🗑️ **Slide to Delete** | Swipe left on any ticket in your list to delete unwanted bills with confirmation. |
| 🔔 **Itemized Email Reminders** | Sends push notifications and styled HTML email breakdowns via Firebase Cloud Functions. |
| 🎫 **Ticket Status Lifecycle** | Track bills seamlessly across `draft → open → partiallyPaid → settled`. |

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| **App Framework** | Flutter 3, Dart 3, Material 3 |
| **State Management** | Riverpod |
| **Authentication** | Firebase Authentication |
| **Database** | Cloud Firestore |
| **Cloud Backend & Emails** | Firebase Cloud Functions (Node 20) + Nodemailer |
| **Push Notifications** | Firebase Cloud Messaging (FCM) |
| **OCR Text Recognition** | `google_mlkit_text_recognition` (on-device) |
| **Exchange Rates** | Open exchange rates API, cached in memory |

---

## 🏗 Architecture

```
┌────────────────────────────── Flutter app ──────────────────────────────┐
│  UI (features/*)  ──▶  Riverpod providers  ──▶  Repositories/Services   │
│  login · tickets · scan · create · detail        TicketRepository        │
│                                                  OcrService · BillParser │
│                                                  CurrencyService         │
└───────────────┬───────────────────────────────────────┬─────────────────┘
                │ Auth / Firestore                      │ HTTPS
                ▼                                       ▼
        ┌───────────────┐                       ┌───────────────┐
        │   Firebase    │                       │  Rates API    │
        │ Auth·Firestore│                       └───────────────┘
        └───────┬───────┘
                │ onCreate: notifications/{id}
                ▼
        ┌────────────────────┐
        │  Cloud Function    │──▶ FCM Push + Itemized HTML Email
        └────────────────────┘
```

**Key Design Decisions**

- **Money is stored as integers in minor units** (cents) with ISO-4217 codes to avoid floating-point rounding errors.
- **Proportional tax & tip allocation** distributes tax fairly based on each participant's food subtotal.
- **Largest-remainder allocation** distributes leftover cents deterministically.
- **Decoupled notifications**: The client queues requests to Firestore; Cloud Functions send FCM push notifications and HTML emails asynchronously.

---

## 📁 Project Structure

```
lib/
├── main.dart
├── app.dart                   # MaterialApp + AuthGate
├── providers.dart             # Riverpod providers
├── core/
│   ├── money.dart             # parse/format/allocate/convert
│   └── currencies.dart
├── models/ticket.dart         # Ticket, TicketItem, Participant
├── data/ticket_repository.dart
├── services/
│   ├── ocr_service.dart       # ML Kit text recognition
│   ├── bill_parser.dart       # OCR text → items/tax/total
│   ├── currency_service.dart
│   └── notification_service.dart
└── features/
    ├── auth/login_screen.dart
    └── tickets/
        ├── tickets_screen.dart
        ├── scan_screen.dart
        ├── create_ticket_screen.dart
        └── ticket_detail_screen.dart
functions/                     # Cloud Function: deliver push & email reminders
firestore.rules
test/                          # unit tests
```

---

## 🚀 Getting Started

Check [SETUP_NOTES.txt](SETUP_NOTES.txt) for a step-by-step setup guide.

### Quick Commands

```bash
# 1. Install dependencies
flutter pub get

# 2. Configure Firebase (generates lib/firebase_options.dart)
flutterfire configure

# 3. Deploy Cloud Functions and Security Rules
firebase deploy --only firestore:rules,functions

# 4. Run automated unit tests
flutter test

# 5. Launch app
flutter run
```

---

## 🗄 Data Model

```
tickets/{id}
  ownerId, title, currency (ISO-4217), source (scan|manual), status
  items[]        { name, amount (minor units), quantity, assignedEmails[] }
  tax, tip       (minor units)
  participants[] { name, email, share, paid, isOwner }
  memberEmails[] (for "tickets shared with me" queries)
  fxRates        (snapshot at creation)
  createdAt

users/{uid}            { email, fcmTokens[] }
notifications/{id}     { ticketId, title, toName, toEmail, ownerName, ownerEmail, amount, currency, items[], tax, subtotal, createdAt }
```

---

## 🧪 Testing

```bash
flutter test          # unit tests (money maths, bill parser, item assignment)
flutter analyze       # static analysis
```

---

## 🗺 Roadmap

- [x] Email/password login
- [x] Google Sign-In
- [x] Manual bill entry
- [x] Multi-currency with rate snapshot
- [x] OCR scanning with review step
- [x] Add participants first & assign specific food items
- [x] Slide to delete ticket (with confirmation)
- [x] Itemized email reminders & push notifications via Cloud Functions
- [ ] Payment QR / PayNow / DuitNow details on tickets
- [ ] Localisation (i18n)

---

## 📄 License

Distributed under the MIT License. See [`LICENSE`](LICENSE).
