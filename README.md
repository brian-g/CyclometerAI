# Cyclometer
Cyclometer is an app that utilizes Bluetooth LE (BLE) devices attached to your bicycle. It is meant to replace the old school bike computers or *cyclometers*. The Cyclometer app will run only on iOS. Cyclometer is designed by a biking enthusiast out of frustration with other generic apps that are more useful for running. The dashboard has clear, legible text that can be seen in the sun and even when the screen is dimmed. The automatic wheel sizing uses the GPS to figure out the precise size of the wheel being used. This algorithm will account for small changes in the size of the wheel due to air pressure and the weight of the rider. After determining the wheel size, the GPS will be turned into adaptive mode and will only be used to track the route taken.

## Overview
The GPS is only used for speed and distance when the BLE cycling speed sensor is not available.

The dashboard has clear legible text that can be seen in the sun and even when the screen is dimmed. All in all Cyclometer has the following innovative features:

* Clear and legible dashboard
* Battery saving features such as auto-dimming and adaptive GPS precision
* Automatic wheel sizing for greater precision and ease of use
* Ability to estimate distances for your routes
* No backend service means no one gets your data except for you
* Integration with bike radars
* Integration with AR glasses

### AR glasses with HUD
* AR glasses will be a future feature, but the architecture should be prepared for it
* Start with the Engo. There is an API and sample applications

### Basic UI requirements
* Support light and dark modes. Dark modes save battery on OLED devices.
* Auto dimming while riding. One tap to brighten and allow interaction. While dimmed, updates should also be restrained unless safety demanded (radar)
* Lock screen Live Activity shows key metrics.
* Watch app. The watch app can show one more widget. The watch can be used as a source of HR data as well.
* Adaptive GPS precision based on the speed and direction of travel.

### Architecture
* SwiftUI based.
* Align with current best practices for Swift development
* Use native Apple frameworks when possibly including: MapKit, CoreLocation, HealthKit, CoreBluetooth, GraphKit
* Bluetooth sensors should be a modular architecture to allow new sensors to be added easily in the future.
* All rides should be stored and accessible via the Apple Files app in the GPSX format.

### Price
The app will be $10, not recurring with a 30-day trial. Use Apple's native payments.

## Service Integrations

The app itself does not require logins to services to work and will support simple GPX file export of ride data. The GPX files

* Strava: Push rides, pull segments and routes
* Map my Ride
* Apple Health: Access weight, height, HR zones, etc for calculating metrics such as calories burned
* Apple Fitness: Push rides, note this should be optional because services such as Strava will also push
* Trailforks: Show trails, push rides
* Tribos.studio: Pull routes
* Helios
* Import/export of GPX files.
* opencyclemap.org for trails

## Sensor Integrations (BT and BLE)

* BLE Heart Rate monitors
* BLE Cycling cadence sensors
* BLE Cycling speed sensors
* Power meters
* Garmin Vario and Wahoo TRAKR
* Pressure monitors like TL Mini Pressure

### Clear and legible dashboard
The design is meant to be as minimal as possible. This has the following benefits:

* Easy to read at a glance
* Battery efficient

### Battery saving features

* Dashboard minimalism
* Automatic dimming of screen
* Adaptive GPS precision

### Automatic wheel sizing
The automatic wheel sizing uses the GPS to figure out the precise size of the wheel being used. This algorithm will account for small changes in the size of the wheel due to air pressure and weight of the rider. After determine the wheel size, the GPS will be turned into adaptive mode and will only be used to track the route taken.

The GPS is only used for speed and distance when the BLE cycling speed sensor is not available.

## Style Guide

### Type and ramp
Type is set with GillSans primarily in the GillSans Light variety. Gill Sans is a humanistic type face with open an large numbers making it ideal for the dashboard where quick reading and understanding of the numbers is important.

Large numbers on the dashboard should use D-Din as the typeface. The font files for this are found in the assets/d-din folder within this project folder.

The ramp is set as:

* Hero: D-Din Condensed 138pt (letter spacing: -6.47)
* Caption: GillSans-Light 14pt
* Major: D-Din 56pt
* Minor: D-Din 14pt
* Values: D-Din 34pt
* Units: GillSans-Light 17pt

GillSans is install on all

Labels should be in **ALL CAPS**
Units should be in *lowercase*

### BikeRider Color System

Primary brand: `#60BD10` · Optimized for outdoor sunlight visibility · WCAG AA+ contrast ratios

---

#### Light Mode

| Token | Hex | Usage |
|-------|-----|-------|
| **Primary** | | |
| `primary` | `#60BD10` | Brand green — CTAs, active states |
| `primaryDark` | `#4A9A08` | Pressed / hover state |
| `primaryLight` | `#E8F5D9` | Tinted backgrounds, chips |
| `primaryMuted` | `#A8D97A` | Secondary accents, icons |
| **Backgrounds** | | |
| `bgPrimary` | `#FFFFFF` | Main app background |
| `bgSecondary` | `#F5F5F5` | Cards, grouped sections |
| `bgTertiary` | `#EBEBEB` | Inset fields, wells |
| `bgElevated` | `#FFFFFF` | Modals, sheets, popovers |
| **Text** | | |
| `textPrimary` | `#000000` | Headlines, critical values |
| `textSecondary` | `#555555` | Descriptions, timestamps |
| `textTertiary` | `#888888` | Placeholders, captions |
| `textOnPrimary` | `#FFFFFF` | Text on primary buttons |
| `textInverted` | `#FFFFFF` | Text on dark fills |
| **Borders & Separators** | | |
| `border` | `#D1D1D1` | Default borders |
| `borderSubtle` | `#E5E5E5` | Dividers, hairlines |
| `borderStrong` | `#999999` | Focused inputs, emphasis |
| **Ratings** | | |
| `ratingBad` | `#D32F2F` | Bad / danger — high saturation for sun |
| `ratingBadBg` | `#FDECEA` | Bad background tint |
| `ratingOkay` | `#ED8B00` | Okay / caution — amber |
| `ratingOkayBg` | `#FFF4E0` | Okay background tint |
| `ratingGood` | `#2E8B08` | Good / success — deep green |
| `ratingGoodBg` | `#E8F5D9` | Good background tint |
| **Heart Rate Zones** | | |
| `hrZone1` | `#90CAF9` | Zone 1 — Recovery (light blue) |
| `hrZone2` | `#1976D2` | Zone 2 — Endurance (blue) |
| `hrZone3` | `#60BD10` | Zone 3 — Tempo (green) |
| `hrZone4` | `#F57C00` | Zone 4 — Threshold (orange) |
| `hrZone5` | `#D32F2F` | Zone 5 — VO₂ Max (red) |
| **System** | | |
| `destructive` | `#C62828` | Delete, destructive actions |
| `info` | `#1565C0` | Info badges, tips |
| `shadow` | `rgba(0,0,0,0.08)` | Elevation shadows |
| `overlay` | `rgba(0,0,0,0.3)` | Modal backdrop |

---

#### Dark Mode

| Token | Hex | Usage |
|-------|-----|-------|
| **Primary** | | |
| `primary` | `#6FD11E` | Brand green — CTAs, active states |
| `primaryDark` | `#60BD10` | Pressed / hover state |
| `primaryLight` | `#1A3006` | Tinted backgrounds, chips |
| `primaryMuted` | `#3D6B12` | Secondary accents, icons |
| **Backgrounds** | | |
| `bgPrimary` | `#0F0F0F` | Main app background |
| `bgSecondary` | `#1A1A1A` | Cards, grouped sections |
| `bgTertiary` | `#252525` | Inset fields, wells |
| `bgElevated` | `#1F1F1F` | Modals, sheets, popovers |
| **Text** | | |
| `textPrimary` | `#FFFFFF` | Headlines, critical values |
| `textSecondary` | `#A0A0A0` | Descriptions, timestamps |
| `textTertiary` | `#666666` | Placeholders, captions |
| `textOnPrimary` | `#000000` | Text on primary buttons |
| `textInverted` | `#000000` | Text on light fills |
| **Borders & Separators** | | |
| `border` | `#3A3A3A` | Default borders |
| `borderSubtle` | `#2A2A2A` | Dividers, hairlines |
| `borderStrong` | `#555555` | Focused inputs, emphasis |
| **Ratings** | | |
| `ratingBad` | `#EF5350` | Bad / danger — high saturation for sun |
| `ratingBadBg` | `#3B1010` | Bad background tint |
| `ratingOkay` | `#FFB020` | Okay / caution — amber |
| `ratingOkayBg` | `#3B2800` | Okay background tint |
| `ratingGood` | `#60BD10` | Good / success — deep green |
| `ratingGoodBg` | `#1A3006` | Good background tint |
| **Heart Rate Zones** | | |
| `hrZone1` | `#64B5F6` | Zone 1 — Recovery (light blue) |
| `hrZone2` | `#42A5F5` | Zone 2 — Endurance (blue) |
| `hrZone3` | `#6FD11E` | Zone 3 — Tempo (green) |
| `hrZone4` | `#FFA726` | Zone 4 — Threshold (orange) |
| `hrZone5` | `#EF5350` | Zone 5 — VO₂ Max (red) |
| **System** | | |
| `destructive` | `#EF5350` | Delete, destructive actions |
| `info` | `#42A5F5` | Info badges, tips |
| `shadow` | `rgba(0,0,0,0.4)` | Elevation shadows |
| `overlay` | `rgba(0,0,0,0.6)` | Modal backdrop |


### Text alignment
Units should always be set baseline aligned with their coorsponding values

### Icons
Icons should use Font Awesome. Font Awesome is downloaded and is in ~/Projects/fontawesome-pro-7.2.0-desktop

### Sounds and Haptics
For warnings and alerts, especially RADAR, the watch extension should be used to give the user hapic alerts in addition to the dashboard. Additionally sounds should also be used in conjunction with the watch haptics. An appropriately set of sounds should be sourced from open source or public domain sounds.

## Pages
This tree represents the page hierarchy and sitemap. The top level is the primary bottom navigation. This is also a liquid glass app.

* Dashboard
* Rides
* Settings

### Dashboard
The dashboard is the primary UI with the user while riding. It should be a configurable widget oriented interface. Each widget shows a piece of information like speed or cadence. The widget customization interaction should be the similar to the iOS launcher screens, that is to say, press and hold to go into edit mode, drag widgets around, remove widgets, and add widgets. When not in edit mode, tapping a widget should open a bottom drawer showing more info about the data being collected. Each widget has sizes: 1x1, 2x1, and 3x1. The dashboard will respond to landscape orientation.

* Scrolling not paging. Assumption is that passing is more difficult to manage while riding (verify)
* The content of the dashboard is :
    * Top bar: All icons
        * GPS strength visualization using the satellite icon and the colors: bad/okay/good
        * Devices
        * Brightness
        * Tapping the top bar will show more details for each of the previous items and allow the brightness to be changed
    * Widgets
    * Bottom bar
        * Dashboard/Rides/Settings navigation. Not shown during an active ride
        * Start/stop
        * Lap
* Widgets
    * Speed
        * Current speed is prominent
        * A watermarked graph in the widget should show the speed history for the current ride. The max speed line should be shown as well as a line for the running average.
        * Average is shown with indicator that displays if the current trend is up or down
        * Max
    * Cadence
        * Current cadence
        * Average
        * Max
    * Power
        * 10s power average
        * 60s power average
    * Ride time
    * Elevation
        * Show total ascent and decent in the 2x1 size.
        * Only show accent in 1x1 size
        * As a watermark, show the elevation provile of the ride
    * Grade
    * Pace
    * Distance
    * Map
        * The map has a mode when the user does a press and hold, then draws a route on the map, the map will display the distance of the route
        * Use the native Apple Maps component.
        * Display the historical path.
        * Show any route being followed.
        * Show Strava segments
        * Other layers
    * Segment: Display of current Strava segment
        * Current time
        * Time under or over the leader
        * PR under/over
    * Heart rate
        * Current HR zone (zones are from Apple Health)
        * Current
        * Average
        * Max
    * HRV
    * Calories burned
    * Respiratory rate
    * SpO2
    * EKG
* Alerts
    * Weather. Warn if conditions in the direction of travel indicates worsen.
    * If following a route, large directions
* Visual display of radar
    * Sound

## Settings
The settings page allows the user to define their connections and options. It has the following sections:

* General section:
    * Auto pause: When on will pause the recording when stopped and start automatically
    * Units: This allows the user to override their device settings
    * Auto dim screen: When on will control if the screen is dimmed after a 30s timeout
    * Set Do Not Disturb: This is similar to driving mode on the phone, but gets rid of the notification distractions while riding
    * Wheel size: Automatic, or the circumference. Automatic will use the GPS to determine the size of the wheel
* Devices: This section shows and allows the user to maintain all of the associated devices.
* Accounts: This section shows associated services.
* About: This section shows the following:
    * Version
    * Privacy
