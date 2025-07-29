# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a native iOS app with widget extension that displays Notion database todos on the iPhone home screen. The app uses SwiftUI and integrates directly with the Notion API.

## Development Commands

### Building and Running
- **Build and run main app**: Open `NotionTodoWidget.xcodeproj` in Xcode and build
- **Widget testing**: Build the main app target which includes the widget extension
- **Debug widget**: Use Xcode's widget simulator or add widget to home screen for testing

### Dependencies
- No external package managers (CocoaPods, SPM packages)
- Uses iOS system frameworks: SwiftUI, WidgetKit, Foundation, Combine

## Architecture

### Core Components

**NotionService.swift** (`NotionTodoWidget/NotionService.swift:5`)
- Singleton service managing all Notion API interactions
- Handles authentication, data fetching, caching, and Notion task updates
- Manages multiple database configurations with active/widget database selection
- Implements comprehensive filtering and sorting with persistent preferences
- Uses App Groups for data sharing between main app and widget

**TodoItem.swift** (`NotionTodoWidget/TodoItem.swift:20`)
- Core data models: `TodoItem`, `TodoStatus`, `TodoPriority`, `SortConfiguration`
- Enums for status and priority with display properties and system icons
- Comprehensive sorting and filtering configuration structures

**PreferencesManager.swift** (`NotionTodoWidget/PreferencesManager.swift:3`)
- Manages persistent storage using both App Groups and UserDefaults
- Handles sort configurations, status/priority filters, and widget database selection
- Dual storage strategy (App Groups + regular UserDefaults) for reliability

**TodoWidget.swift** (`TodoWidgetExtension/TodoWidget.swift:100`)
- Widget implementation using AppIntentConfiguration for iOS 17+ interactive widgets
- Supports database selection through widget configuration
- Smart caching strategy with multiple fallback mechanisms for data retrieval
- Handles authentication states and empty data scenarios

### App Groups Integration
- App Group ID: `group.com.nirneu.notiontodowidget`
- Used for sharing data between main app and widget extension
- All preferences and cached todos stored in both App Groups and regular UserDefaults as fallback

### URL Scheme Integration
- **Custom URL Scheme**: `notiontodowidget://`
- **Widget Navigation**: `notiontodowidget://open?database=[databaseId]` - Opens app and switches to specified database
- **Todo Editing**: `notiontodowidget://edit/[todoId]?database=[databaseId]` - Opens app, switches database, and shows todo detail
- **Database Management**: `notiontodowidget://change-database` - Opens database manager
- **Smart Database Switching**: URLs automatically switch main app to the database context of the widget

### Data Flow
1. **Authentication**: User provides Notion API key and database configurations
2. **Data Fetching**: `NotionService` fetches database schema then todos from all configured databases
3. **Processing**: Todos are parsed, filtered, sorted based on user preferences for each database
4. **Caching**: Processed (filtered/sorted) data saved to App Groups with database-specific keys
5. **Widget Updates**: `WidgetCenter.shared.reloadAllTimelines()` triggered after data changes
6. **Bi-directional Updates**: App can update Notion tasks (status, priority, due date, title) with optimistic local updates
7. **Preference Changes**: When filters/sorting change, all database caches are refreshed with new preferences

### Key Patterns

**Database Management**
- Multiple database support with `DatabaseConfiguration` model
- Active database for main app, completely separate widget database selection
- **Inline Database Switching**: Quick database picker in main screen header for easy switching
- **Advanced Management**: Separate "Manage Databases" view for CRUD operations (add/edit/remove)
- **Database Operations**: Add (`addDatabase`), Update (`updateDatabase`), Remove (`removeDatabase`) methods
- Database switching triggers schema fetch and data refresh for all databases
- Automatic data caching for all configured databases to support widget configuration
- Database removal and updates clean up associated cached data

**Filtering & Sorting**
- Persistent preferences for status/priority filters shared across all databases
- Primary and secondary sort options with ascending/descending orders
- **Universal Application**: Filtering and sorting preferences apply to ALL databases, not just the active one
- **Real-time Updates**: When preferences change, all database caches are refreshed with new filters/sorting
- Filtered and sorted data cached for consistent widget display regardless of selected database

**Widget Data Strategy**
- **Independent Widget Configuration**: Widget database selection works independently from main app's active database
- **Smart Default Configuration**: New widgets automatically default to the current active database in configuration UI
- **Database-Specific Caching**: Data cached with keys `cachedTodos_[databaseId]` for each configured database
- **Priority-Based Data Loading**: 
  1. Widget-configured database (takes absolute priority)
  2. Current active database (fallback for unconfigured widgets)
  3. General cached data (final fallback)
- **Automatic Data Fetching**: When widget database is changed, data is automatically fetched and cached
- **Smart Navigation**: Widget taps automatically switch main app to the widget's configured database
- Timeline refresh every 5 minutes for cached data, 15 minutes for demo data

**Error Handling & Debugging**
- Comprehensive logging throughout data flow
- Debug files saved to Documents directory (`notion_schema.json`, `notion_todos.json`)
- Graceful fallbacks for network errors and missing data

## Notion API Integration

### Database Schema Requirements
The Notion database should have these properties:
- **Task name** (Title): The todo item title  
- **Status** (Status/Select): Not started, In progress, Done, Cancelled, Blocked, Research
- **Priority** (Select): Low, Medium, High, Urgent
- **Due Date** (Date): Optional due date

### API Endpoints Used
- `GET /v1/databases/{database_id}` - Fetch database schema
- `POST /v1/databases/{database_id}/query` - Query todos
- `PATCH /v1/pages/{page_id}` - Update task properties

### Property Mapping
- **Status**: Supports both new "status" property type and legacy "select" type
- **Priority**: Select property with exact enum matching
- **Due Date**: Date property with start date extraction
- **Title**: Flexible title property detection (Task name, Name, Title, etc.)

## File Structure Notes

- **Main App**: `NotionTodoWidget/` contains the main iOS app
- **Widget Extension**: `TodoWidgetExtension/` contains the widget implementation  
- **Shared Code**: `TodoItem.swift`, `NotionService.swift`, and `PreferencesManager.swift` are shared between targets
- **App Groups**: Both targets configured with the same App Group for data sharing

## User Interface Design

**Main Screen Layout**
- Database picker at top with current database name and task count
- Quick database switching via dropdown menu without leaving main screen
- "Manage Databases" option in database picker for advanced operations (add/remove)
- Filter and sort controls in toolbar for persistent preferences across all databases

**Database Management UX**
- **Primary**: Inline database picker for frequent switching between existing databases
- **Secondary**: Dedicated management screen focused purely on database CRUD operations
  - Add new databases with name and Notion database URL (auto-extracts ID)
  - Edit existing database names and URLs
  - Delete databases with automatic cache cleanup
  - No selection UI (handled by main screen picker)
  - **User-Friendly Setup**: Clear instructions and automatic URL-to-ID extraction
- Reduced friction for common task of switching between work/personal/project databases

## Recent Development History & Important Memories

### Database Setup UX Improvements (July 2025)
**Critical Implementation Details:**
- **Automatic Database Name Fetching**: Added `fetchDatabaseInfo` API method in `NotionService.swift` that calls Notion's `/v1/databases/{id}` endpoint to extract database names automatically
- **Simplified Database Forms**: Removed manual database name input field - users now only paste Notion URL and system auto-fills both ID and name
- **Enhanced Instructions**: Updated both Add/Edit database forms with clear warnings about using source database (not filtered views)
  - Step 1: "Go to your source database (not a filtered view)" with orange warning "⚠️ Important: Must be the main database, not a view"
  - Step 2: "Click the '•••' menu → 'Copy link to view'"  
  - Step 3: "Paste the URL below - we'll extract the ID and name automatically"
- **URL-to-ID Extraction**: `extractDatabaseId` function in `DatabaseManagerView` handles various Notion URL formats and regex patterns
- **Real-time Feedback**: Loading indicators and success states show during database name fetching

### Widget Configuration Bug Fixes
**Critical Bug Resolved**: New widgets showed "Database" placeholder instead of active database name in configuration
- **Root Cause**: `DatabaseSelectionIntent.init()` wasn't setting default database for new widgets
- **Solution**: Enhanced init() method to automatically fetch and set current active database as default
- **Supporting Infrastructure**: Added `getCurrentActiveDatabaseSync()` and `DatabaseEntity.createDefault()` methods
- **Verification**: Widget configuration now properly displays actual database name (e.g., "Work Tasks Tracker") instead of generic placeholder

### Code Quality & iOS 17+ Compatibility
- **Fixed Deprecation Warnings**: Updated `onChange(of:perform:)` to modern `onChange(of:initial:_:)` syntax with oldValue/newValue parameters
- **Cleaned Unused Variables**: Optimized variable usage patterns to eliminate compiler warnings
- **Debug Logging**: Added comprehensive logging throughout widget configuration and database fetching flows for troubleshooting

### Key User Experience Patterns Established
1. **Database Setup Flow**: User pastes Notion URL → System extracts ID and fetches name → Form auto-populates → User clicks Add/Save
2. **Widget Configuration Flow**: Add widget → Automatically defaults to active database → Shows actual database name in configuration
3. **Source Database Emphasis**: Clear visual warnings prevent users from accidentally using filtered views instead of source databases

### Important Technical Notes for Future Development
- **Database Name Fetching**: Always use `NotionService.fetchDatabaseInfo()` for getting database names from Notion API
- **Widget Defaults**: New widgets must initialize with active database via `DatabaseSelectionIntent.init()` to show proper configuration
- **Form Instructions**: Both Add/Edit database forms must have identical instruction text with source database warnings
- **URL Extraction**: `extractDatabaseId()` handles multiple Notion URL formats including query parameters and hashed IDs
- **iOS Version Compatibility**: Use modern `onChange` syntax for iOS 17+ compatibility

## Common Development Tasks

When making changes to data models, ensure both app and widget targets are updated. When modifying the widget, test thoroughly as widget debugging can be challenging. For Notion API changes, verify property name mappings and update parsing logic accordingly.

**Database Setup Changes**: If modifying database configuration flow, ensure both automatic name fetching and URL extraction continue working. Test with various Notion URL formats and verify widget configuration defaults work properly.