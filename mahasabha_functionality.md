# ABKM Community Platform Functionality Document

This document provides a detailed overview of the pages, roles, scenarios, and permissions within the ABKM (Akhil Bhartiya Kushwaha Mahasabha) application.

## 1. User Roles & Permissions Matrix

| Feature / Action | Member | Moderator | Admin | SuperUser | Blocked |
|-----------------|:---:|:---:|:---:|:---:|:---:|
| Login via OTP | ✅ | ✅ | ✅ | ✅ | ❌ |
| View Profile | ✅ | ✅ | ✅ | ✅ | ❌ |
| Edit Own Profile | ✅ | ✅ | ✅ | ✅ | ❌ |
| Browse Discover (Profiles) | ✅ | ✅ | ✅ | ✅ | ❌ |
| Join Events | ✅ | ✅ | ✅ | ✅ | ❌ |
| Create Events | ❌ | ✅ | ✅ | ✅ | ❌ |
| Manage Own Events | ❌ | ✅ | ✅ | ✅ | ❌ |
| Invite Members to Events | ❌ | ✅ | ✅ | ✅ | ❌ |
| View Activity Feed | ✅ | ✅ | ✅ | ✅ | ❌ |
| Access Admin Dashboard | ❌ | ❌ | ✅ | ✅ | ❌ |
| Promote/Demote Users | ❌ | ❌ | ✅ | ✅ | ❌ |
| Delete Any Event | ❌ | ❌ | ✅ | ✅ | ❌ |
| Block/Unblock Users | ❌ | ❌ | ✅ | ✅ | ❌ |
| Complete Data Cleanup | ❌ | ❌ | ❌ | ✅ | ❌ |

---

## 2. Detailed Page Overviews

### 2.1 Authentication Screen (`AuthScreen`)
- **Purpose**: Secure entry point for all users.
- **Workflow**: 
    - Enter 10-digit mobile number.
    - Receive and enter a 4-digit OTP.
    - Automatic profile check: New users are sent to the profile creation flow; existing users proceed to the Home Screen.
- **Restrictions**: Blocked users receive an "Account Blocked" notice and cannot proceed.

### 2.2 Home Screen (`HomeScreen`)
The Home Screen is dynamic and changes its layout and navigation options based on the user's role.

- **Discover View**:
    - Accessible to all roles.
    - Shows a sorted list of community members based on seniority (Patron > President > ... > Member).
    - Advanced search functionality (by name, profession, location, etc.).
- **Hosting View**:
    - Accessible to **Moderators, Admins, and SuperUsers**.
    - Displays "I'm Hosting" (Upcoming) and "I've Hosted" (Past) event sections.
    - Allows quick access to event management and attendee lists.
- **Create View**:
    - Accessible to **Moderators, Admins, and SuperUsers**.
    - Launches the `AddEventScreen` to create a new community gathering.
- **Manage View (Admin Dashboard)**:
    - Accessible to **Admins and SuperUsers**.
    - Displays a summary of the community (Total Members, Active Events).
    - Quick links to User Management and Data Cleanup.

### 2.3 Profile Screen (`ProfileScreen`)
- **Purpose**: Manage personal data.
- **Sections**:
    - **Personal**: Name, DOB (automatically calculates age), Bio, Profile Picture.
    - **Location**: State, District, Tehsil, Village.
    - **Professional**: Sector, Profession, Education Level, Degree.
    - **Referral**: Mobile number of the person who introduced the user.
- **Logic**: Users must complete their profile before appearing in the Discover list.

### 2.4 Public Profile Screen (`PublicProfileScreen`)
- **Purpose**: View details of other community members.
- **Features**:
    - Click-to-call and Click-to-WhatsApp.
    - Hierarchical position display.
    - **Admin Tools**: Visible only to Admins/SuperUsers. Allows promoting a member to Moderator/Admin or demoting them.

### 2.5 Add Event Screen (`AddEventScreen`)
- **Purpose**: Formalize a community gathering.
- **Fields**: Title, Date/Time, Event Type (Meeting, Rally, etc.), Location (State/Tehsil/City), Meeting Point, and Description.
- **Workflow**: Once created, the event appears in the "Hosting" view for the creator.

### 2.6 Event Details Screen (`EventDetailsScreen`)
- **Purpose**: Deep dive into a specific event.
- **For Attendees**:
    - View description, location, and host.
    - Tap "Join Now" to request/register attendance.
- **For Hosts**:
    - Manage "Join Requests".
    - "Invite Members": Search the directory to send invitations.
    - Edit or Delete the event.

### 2.7 Activity Screen (`ActivityScreen`)
- **Purpose**: Unified notification hub.
- **Functionality**:
    - Displays status updates for event applications (Approved/Declined).
    - Shows incoming Invitations with "Accept" or "Deny" buttons.
    - Keeps a history of all community interactions.

### 2.8 Member Directory (`MemberDirectoryScreen`)
- **Purpose**: A full list of community members.
- **Features**: Specialized filtering by hierarchy level (National, State, District, etc.).

### 2.9 Promotion Management (`PromotionManagementScreen`)
- **Purpose**: Review role changes.
- **Functionality**: Tracks the history of who was promoted to what role and by whom.

---

## 3. Core Scenarios

### Scenario A: New User Onboarding
1. User enters mobile number in `AuthScreen`.
2. OTP is verified.
3. System detects no profile exists.
4. User is redirected to `ProfileScreen` (Edit Mode).
5. User fills in required fields and saves.
6. Profile is uploaded to Supabase, and the user is redirected to `HomeScreen`.

### Scenario B: SuperUser Promoting a Member
1. SuperUser searches for a member in the Discover View.
2. Taps on the member to open `PublicProfileScreen`.
3. Taps the "Admin Settings" button (exclusive to Admins).
4. Selects a new Position (e.g., "State President") and Role ("Admin").
5. Supabase is updated; the user's role and seniority change immediately in the next sync.

### Scenario C: Moderator Hosting an Event
1. Moderator taps the "Create" icon in the Bottom Nav.
2. Fills in event details in `AddEventScreen`.
3. Saves the event.
4. Taps on the new event in the "Hosting" view.
5. Taps "Invite Members" to proactively reach out to specific community leaders.

---

## 4. Permission Safeguards (What Role is NOT Allowed to Do)

- **Members** cannot see the "Hosting" or "Manage" tabs. They cannot access the "Admin Settings" on any public profile.
- **Moderators** can create events but cannot promote other users to Moderator or Admin roles.
- **Blocked Users** are immediately kicked out of the app. A background timer in `HomeScreen` checks for permission changes every 5 seconds to ensure blocked users cannot stay in a session.
- **General Admins** can manage everything except for "Complete Data Cleanup," which is reserved for the **SuperUser** to prevent accidental data loss.
