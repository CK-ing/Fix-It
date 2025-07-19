# Fix It App (A186687)

## Fix It - Home Maintenance Service App
Fix It is a cross-platform mobile application built with Flutter that connects homeowners with skilled handymen for various home repair and maintenance services. The platform serves as a two-sided marketplace, providing a streamlined workflow for booking, managing payments, and leaving reviews.

This project was developed as a final year project, demonstrating a full-stack implementation using modern mobile development practices and a robust backend-as-a-service architecture.

## Key Features
- Role-Based Authentication: Separate sign-up and login flows for "Homeowners" and "Handymen" using Firebase Auth (Email/Password and Google Sign-In).
- Service Management: Handymen can create, update, and de-list their service offerings (CRUD). Implements a "soft delete" feature to maintain data integrity for historical bookings.
- Real-time Booking System: A complete, multi-status booking workflow (Pending, Accepted, En Route, Completed, Cancelled) with real-time updates for both users.
- Custom Job Requests: Homeowners can submit custom job requests with photos and a budget. Handymen can review these requests and respond with specific quotes.
- Push Notifications: Uses Firebase Cloud Functions (FCM) to send real-time push notifications for important events like new bookings, status updates, new quotes, and new reviews.
- Ratings and Reviews: A comprehensive review system allowing homeowners to rate services and leave comments with photos. Ratings are aggregated and displayed on service and handyman profiles.
- Handyman Statistics Dashboard: A data-rich dashboard for handymen to track their revenue, job history, and performance with filterable charts and trend indicators.
- In-App Chat: Real-time messaging between homeowners and handymen within the context of a booking.
- AI-Powered Chatbot: An intelligent assistant designed to answer frequently asked questions (FAQs) for both homeowners and handymen, providing instant support.
- AI-Powered Image Recognition: An artificial intelligent that recognizes uploaded images to automatically generate title and descriptions of home maintenance issues.
- AI live camera home repair issues detection: Implement Tensorflowlite, Flutter Vision and Gemini API for fast & accurate detection of home repair issues

## Technology Stack
- Framework: Flutter
- Language: Dart
- Backend: Firebase (Backend-as-a-Service)
  - Database: Realtime Database (RTDB)
  - Authentication: Firebase Auth
  - Storage: Firebase Storage for user-uploaded images.
  - Serverless Functions: Firebase Cloud Functions for sending push notifications.
  - AI Chatbot: Google Gemini API for the intelligent chatbot.
  - Live AI Camera Home Repair Issues Detection: TensorFlow Lite (TFLite), Flutter Vision, Google Gemini API and manually trained YOLOv8 model (real-time object detection)
- Key Packages:
  - firebase_core, firebase_auth, firebase_database, firebase_storage
  - firebase_messaging, flutter_local_notifications for push notifications
  - fl_chart for the statistics dashboard
  - image_picker for photo uploads
  - geolocator, geocoding for location-based features
  - url_launcher for making calls and sending emails

