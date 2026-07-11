# Spending Tracker
A spending tracker app built with flutter. Works offline and can sync data to google spreadsheet. Have gemini to help analyze spending habit.

## 🛠️ How to Set Up and Run the App
Download the Project
```bash
git clone https://github.com/YOUR_USERNAME/spending_tracker.git
cd spending_tracker
```
## 🔐 Setting Up Your Keys (.env)
To unlock the Google Sheets backup and AI Copilot features, you need to add your personal setup keys.

Create a file named exactly .env in the root folder of your project:
```plaintext
your_project_root/
├── .env         <─── Create this file here!
├── lib/
├── pubspec.yaml
└── ...
```
Open your new .env file and paste the following layout, replacing the placeholders with your actual keys
```plaintext
SPREADSHEET_ID=<placeholder>
GCP_TYPE=<placeholder>
GCP_PROJECT_ID=<placeholder>
GCP_PRIVATE_KEY_ID=<placeholder>
GCP_PRIVATE_KEY=<placeholder>
GCP_CLIENT_EMAIL=<placeholder>
GCP_CLIENT_ID=<placeholder>
GEMINI_API_KEY=<placeholder>
```
## 🔗 Where to Get Free API Keys
### Get Gemini AI Key
1. Go to Google AI Studio and log in with your Google account.

2. Click the Get API key button in the sidebar menu.

3. Click Create API Key, copy your code string, and paste it into GEMINI_API_KEY in your .env file.

### Get Google Sheets ID & Connection
1. Enable the Sheets Service: Go to the Google Cloud Console, create a project, search for Google Sheets API, and click Enable.

2. Create a Service Email: Go to IAM & Admin > Service Accounts, create a service account, and download its credentials as a JSON file. Copy the specific service account email address generated for you.

3. Get Sheet ID: Open a blank Google Sheet in your browser. Look at the web address bar—copy the long string of letters and numbers in the middle of the link (between /d/ and /edit). Paste this into SPREADSHEET_ID in your .env file.

4. Share Permissions: Click the blue Share button inside your Google Sheet. Paste your service account email address, set its role to Editor, and click save.

## 🏃 Running the App
Install Dependencies
```bash
flutter pub get
```
Generate App Icons
```bash
dart run flutter_launcher_icons
```
Connect physical phone, then run this commands to run the flutter app:
```bash
flutter run --release
```
## ☕ Support & Donate
If this project helped you out—or if you just want to buy me a coffee to support my work—you can do so [here](https://saweria.co/anandailyasa).

Thank youu..! 🤗
