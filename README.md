# Notion Todo Widget

An iOS app with widget extension that displays your Notion database todos on your iPhone home screen.

## Features

- 📱 Native iOS app built with SwiftUI
- 🏠 Home screen widget displaying your todos
- 🔗 Direct integration with Notion API
- 🎨 Clean, modern design matching iOS design patterns
- 🔄 Automatic data syncing between app and widget
- 📊 Support for task priorities, status, and due dates

## Screenshots

*Add screenshots of your app and widget here*

## Setup

### Prerequisites

- iOS 16.0 or later
- Xcode 15.0 or later
- Notion account with API access

### Notion Setup

1. Go to [Notion Developers](https://developers.notion.com/)
2. Create a new integration and get your API token
3. Share your database with the integration
4. Copy your database ID from the URL

### Installation

1. Clone this repository
2. Open `NotionTodoWidget.xcodeproj` in Xcode
3. Build and run the app
4. Enter your Notion API key and database ID
5. Add the widget to your home screen

## Database Schema

Your Notion database should have these properties:
- **Task name** (Title): The todo item title
- **Status** (Select): Not started, In progress, Done, Cancelled
- **Priority** (Select): Low, Medium, High, Urgent
- **Due Date** (Date): Optional due date

## Architecture

- **NotionTodoWidget**: Main iOS app
- **TodoWidgetExtension**: Widget extension for home screen
- **App Groups**: Shared data container for app-widget communication
- **NotionService**: API integration and data management

## License

This project is open source. Feel free to use and modify as needed.