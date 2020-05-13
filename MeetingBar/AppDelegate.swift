//
//  AppDelegate.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.04.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa
import EventKit
import SwiftUI

struct LinksRegex {
    static let meet = try! NSRegularExpression(pattern: #"https://meet.google.com/.*"#)
    static let zoom = try! NSRegularExpression(pattern: #"https://zoom.us/j/.*"#)
}

enum AuthResult {
    case success(Bool), failure(Error)
}

enum meetLinksBrowser: Int {
    case DefaultBrowser = 0
    case Chrome = 1
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!

    private let eventStore = EKEventStore()
    private var calendar: EKCalendar?

    func applicationDidFinishLaunching(_: Notification) {
        eventStoreAccessCheck(eventStore: eventStore, completion: { result in
            switch result {
            case .success(let granted):
                if granted {
                    NSLog("Access to Calendar is granted")
                    self.setup()
                } else {
                    NSLog("Access to Calendar is denied")
                    NSApplication.shared.terminate(self)
                }
            case .failure(let error):
                NSLog(error.localizedDescription)
                NSApplication.shared.terminate(self)
            }
        })
    }

    func setup() {
        DispatchQueue.main.async {
            let calendarTitle = (UserDefaults.standard.string(forKey: "calendarTitle") ?? "")
            self.calendar = getCalendar(title: calendarTitle, eventStore: self.eventStore)

            let statusBar = NSStatusBar.system
            self.statusBarItem = statusBar.statusItem(
                withLength: NSStatusItem.variableLength)

            let statusBarMenu = NSMenu(title: "Meeter in Status Bar Menu")
            self.statusBarItem.menu = statusBarMenu

            self.updateStatusBarMenu()
            self.updateStatusBarTitle()

            self.scheduleUpdateEvents()
            self.scheduleUpdateStatusBarTitle()
        }
    }

    private func scheduleUpdateStatusBarTitle() {
        let activity = NSBackgroundActivityScheduler(identifier: "leits.MeetingBar.updatestatusbartitle")

        activity.repeats = true
        activity.interval = 60
        activity.qualityOfService = QualityOfService.userInitiated

        activity.schedule { (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            NSLog("Firing reccuring reloadStatusBarTitle")
            self.updateStatusBarTitle()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
    }

    private func scheduleUpdateEvents() {
        // TODO: Subscribe to update evenets notification instead of force reload all events
        // https://developer.apple.com/documentation/eventkit/updating_with_notifications

        let activity = NSBackgroundActivityScheduler(identifier: "leits.MeetingBar.updateevents")

        activity.repeats = true
        activity.interval = 60 * 5
        activity.qualityOfService = QualityOfService.utility

        activity.schedule { (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            NSLog("Firing reccuring updateEvents")
            self.updateStatusBarMenu()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
    }

    func loadTodayEventsFromCalendar(_ calendar: EKCalendar) -> [EKEvent] {
        let todayMidnight = Calendar.current.startOfDay(for: Date())
        let tomorrowMidnight = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!

        let predicate = eventStore.predicateForEvents(withStart: todayMidnight, end: tomorrowMidnight, calendars: [calendar])
        let calendarEvents = eventStore.events(matching: predicate)

        NSLog("Calendar \(calendar.title) loaded")
        return calendarEvents
    }

    func updateStatusBarTitle() {
        var title = "🗓️"

        if calendar != nil {
            let nextEvent = getNextEvent(eventStore: eventStore, calendar: calendar!)
            if let nextEvent = nextEvent {
                let nextMinute = Date().addingTimeInterval(60)
                let eventTitle = String((nextEvent.title)!)
                var msg = ""
                if (nextEvent.startDate)! < nextMinute, (nextEvent.endDate)! > nextMinute {
                    let eventEndTime = nextEvent.endDate.timeIntervalSinceNow
                    let minutes = String(Int(eventEndTime) / 60)
                    msg = " now (\(minutes) min left)"
                } else {
                    let eventStartTime = nextEvent.startDate.timeIntervalSinceNow
                    let minutes = Int(eventStartTime) / 60
                    if minutes < 60 {
                        msg = " in \(minutes) min"
                    } else if minutes < 120 {
                        msg = " in 1 hour"
                    } else {
                        let hours = minutes / 60
                        msg = " in \(hours) hours"
                    }
                }
                // TODO: Make title length customizable
                title = "\(eventTitle)\(msg)"
            } else {
                title = "🏁"
            }
        } else {
            NSLog("No loaded calendar")
        }
        DispatchQueue.main.async {
            if let button = self.statusBarItem.button {
                button.title = "\(title)"
            }
        }
    }

    func updateStatusBarMenu() {
        let statusBarMenu = statusBarItem.menu!
        statusBarMenu.removeAllItems()

        if calendar != nil {
            createJoinNextSection(menu: statusBarMenu)
            statusBarMenu.addItem(NSMenuItem.separator())

            createTodaySection(menu: statusBarMenu)
            statusBarMenu.addItem(NSMenuItem.separator())
        }

        createPreferencesSection(menu: statusBarMenu)
        statusBarMenu.addItem(
            withTitle: "About",
            action: #selector(AppDelegate.about),
            keyEquivalent: "")
        statusBarMenu.addItem(NSMenuItem.separator())

        statusBarMenu.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quit),
            keyEquivalent: "")
    }
    
    func createJoinNextSection(menu: NSMenu){
        // TODO: Make shortcut global
        menu.addItem(
            withTitle: "Join next meeting",
            action: #selector(AppDelegate.joinNextMeeting),
            keyEquivalent: "j")
    }

    func createPreferencesSection(menu: NSMenu) {
        // Main preferences menu
        let preferencesMenu = NSMenu(title: "Preferences")

        let preferencesItem = menu.addItem(
            withTitle: "Preferences",
            action: nil,
            keyEquivalent: "")

        preferencesItem.submenu = preferencesMenu
        
        // Calendar submenu
        let calendarItem = preferencesMenu.addItem(
            withTitle: "Calendar",
            action: nil,
            keyEquivalent: "")

        let calendarMenu = NSMenu(title: "Calendar selector")
        calendarItem.submenu = calendarMenu

        let defaultCalendarTitle = UserDefaults.standard.string(forKey: "calendarTitle")
        let calendars = eventStore.calendars(for: .event)
        for calendar in calendars {
            let calendarItem = calendarMenu.addItem(
                withTitle: "\(calendar.title)",
                action: #selector(AppDelegate.selectCalendar(sender:)),
                keyEquivalent: "")
            calendarItem.representedObject = calendar
            if defaultCalendarTitle != nil, defaultCalendarTitle == calendar.title {
                calendarItem.state = .on
            }
        }
        
        // Browser for meet links submenu
        let meetBrowserItem = preferencesMenu.addItem(
            withTitle: "Browser for meet links",
            action: nil,
            keyEquivalent: "")

        let meetBroswerMenu = NSMenu(title: "Meet browser selector")
        meetBrowserItem.submenu = meetBroswerMenu
        
        // Default Browser
        let defaultBrowser = meetBroswerMenu.addItem(
            withTitle: "Default Browser",
            action: #selector(AppDelegate.selectMeetBrowser(sender:)),
            keyEquivalent: "")
        defaultBrowser.tag = meetLinksBrowser.DefaultBrowser.rawValue
        
        // Chrome
        let chrome = meetBroswerMenu.addItem(
            withTitle: "Chrome",
            action: #selector(AppDelegate.selectMeetBrowser(sender:)),
            keyEquivalent: "")
        chrome.tag = meetLinksBrowser.Chrome.rawValue
        
        let browserForMeetLinks = meetLinksBrowser(rawValue: UserDefaults.standard.integer(forKey: "browserForMeetLinks"))
        switch browserForMeetLinks{
        case .DefaultBrowser:
            defaultBrowser.state = .on
        case .Chrome:
            chrome.state = .on
        default:
            break
        }

    }
    
    @objc func selectMeetBrowser(sender: NSMenuItem){
        let selectedBrowser = meetLinksBrowser(rawValue: sender.tag)!
        UserDefaults.standard.set(selectedBrowser.rawValue, forKey: "browserForMeetLinks")
        sender.state = .on
        for item in sender.menu!.items{
            if item != sender {
                item.state = .off
            }
        }
    }

    func createTodaySection(menu: NSMenu) {
        let events: [EKEvent] = loadTodayEventsFromCalendar(calendar!)
        let now = Date()

        // Today header
        let todayFormatter = DateFormatter()
        todayFormatter.dateFormat = "E, d MMM"
        let todayDate = todayFormatter.string(from: now)
        let todayTitle = "Today meetings (\(todayDate)):"
        let titleItem = menu.addItem(
            withTitle: todayTitle,
            action: nil,
            keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(string: todayTitle, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 13)])

        let sortedEvents = events.sorted(by: { $0.startDate < $1.startDate })
        for event in sortedEvents {
            let eventTitle = String(event.title)

            let eventTimeFormatter = DateFormatter()
            eventTimeFormatter.dateFormat = "HH:mm"
            let eventStartTime = eventTimeFormatter.string(from: event.startDate)
            let eventEndTime = eventTimeFormatter.string(from: event.endDate)
            let eventDurationMinutes = String(event.endDate.timeIntervalSince(event.startDate) / 60)
            
            // Event Item
            let itemTitle = "\(eventStartTime) - \(eventTitle)"
            let eventItem = menu.addItem(
                withTitle: itemTitle,
                action: #selector(AppDelegate.clickOnEvent(sender:)),
                keyEquivalent: "")
            if event.endDate < now {
                eventItem.state = .on
            } else if event.startDate < now, event.endDate > now {
                eventItem.state = .mixed
            } else {
                eventItem.state = .off
            }
            eventItem.representedObject = event

            let eventMenu = NSMenu(title: "Item \(eventTitle) menu")
            eventItem.submenu = eventMenu
            
            // Title
            let titleItem = eventMenu.addItem(withTitle: eventTitle, action: nil, keyEquivalent: "")
            titleItem.attributedTitle = NSAttributedString(string: eventTitle, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 15)])
            eventMenu.addItem(NSMenuItem.separator())

            // Duration
            let durationTitle = "\(eventStartTime) - \(eventEndTime) (\(eventDurationMinutes) minutes)"
            eventMenu.addItem(withTitle: durationTitle, action: nil, keyEquivalent: "")
            eventMenu.addItem(NSMenuItem.separator())

            // Status
            var status: String
            switch event.status {
            case .canceled:
                status = " 👎 Canceled"
            case .confirmed:
                status = " 👍 Confirmed"
            case .tentative:
                status = " ☝️ Tentative"
            default:
                status = " ❔ None"
            }
            eventMenu.addItem(withTitle: "Status: \(status)", action: nil, keyEquivalent: "")
            eventMenu.addItem(NSMenuItem.separator())

            // Location
            if event.location != nil {
                eventMenu.addItem(withTitle: "Location:", action: nil, keyEquivalent: "")
                eventMenu.addItem(withTitle: "\(event.location!)", action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Organizer
            if let eventOrganizer = event.organizer {
                eventMenu.addItem(withTitle: "Organizer:", action: nil, keyEquivalent: "")
                let organizerName = eventOrganizer.name ?? ""
                eventMenu.addItem(withTitle: "\(organizerName)", action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }
            
            // Notes
            if event.hasNotes {
                let notes = cleanUpNotes(event.notes!)
                if notes.count > 0 {
                    eventMenu.addItem(withTitle: "Notes:", action: nil, keyEquivalent: "")
                    let item = eventMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
                    item.attributedTitle = NSAttributedString(string: notes)
                    eventMenu.addItem(NSMenuItem.separator())
                }
            }

            // Attendees
            if event.hasAttendees {
                let attendees: [EKParticipant] = event.attendees!
                let count = attendees.filter{ $0.participantType == .person }.count
                eventMenu.addItem(withTitle: "Attendees (\(count)):", action: nil, keyEquivalent: "")
                for attendee in attendees {
                    if attendee.isCurrentUser || attendee.participantType != .person {
                        continue
                    }
                    var attributes: [NSAttributedString.Key: Any] = [:]

                    var roleMark: String
                    switch attendee.participantRole {
                    case .optional:
                        roleMark = "*"
                    default:
                        roleMark = ""
                    }
                    
                    var status: String
                    switch attendee.participantStatus {
                    case .declined:
                        status = ""
                        attributes[NSAttributedString.Key.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                        attributes[NSAttributedString.Key.strikethroughColor] = NSColor.gray
                    case .tentative:
                        status = " [tentative]"
                    case .pending:
                        status = " [?]"
                    default:
                        status = ""
                    }

                    let itemTitle = "- \(attendee.name!)\(roleMark) \(status)"
                    let item = eventMenu.addItem(withTitle: itemTitle, action: nil, keyEquivalent: "")
                    item.attributedTitle = NSAttributedString(string: itemTitle, attributes: attributes)
                }
            }
        }
    }
    
    @objc func about(_: NSStatusBarButton) {
        NSLog("User click About")
        let projectLink = "https://github.com/leits/MeetingBar"
        openLinkInDefaultBrowser(projectLink)
    }

    @objc func quit(_: NSStatusBarButton) {
        NSLog("User click Quit")
        NSApplication.shared.terminate(self)
    }

    @objc func selectCalendar(sender: NSMenuItem) {
        UserDefaults.standard.set(sender.title, forKey: "calendarTitle")
        calendar = sender.representedObject as? EKCalendar
        NSLog("Set \(sender.title) as default calendar")
        updateStatusBarMenu()
        updateStatusBarTitle()
    }

    @objc func joinNextMeeting(_: NSStatusBarButton) {
        NSLog("Click on join next event!")
        let nextEvent = getNextEvent(eventStore: eventStore, calendar: calendar!)
        if nextEvent == nil {
            NSLog("No next event")
            return
        }
        openEvent(nextEvent!)
    }

    @objc func clickOnEvent(sender: NSMenuItem) {
        NSLog("Click on event (\(sender.title))!")
        let event: EKEvent = sender.representedObject as! EKEvent
        openEvent(event)
    }
}

func getNextEvent(eventStore: EKEventStore, calendar: EKCalendar) -> EKEvent? {
    var nextEvent: EKEvent?

    let now = Date()
    let nextMinute = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
    let todayMidnight = Calendar.current.startOfDay(for: now)
    let tomorrowMidnight = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!

    let predicate = eventStore.predicateForEvents(withStart: nextMinute, end: tomorrowMidnight, calendars: [calendar])
    let nextEvents = eventStore.events(matching: predicate)
    // If the current event is still going on,
    // but the next event is closer than 10 minutes later
    // then show the next event
    for event in nextEvents {
        if event.status == .canceled {
            continue
        } else {
            if nextEvent == nil {
                nextEvent = event
                continue
            } else {
                let soon = now.addingTimeInterval(600) // 10 min from now
                if event.startDate < soon {
                    nextEvent = event
                } else {
                    break
                }
            }
        }
    }
    return nextEvent
}

func openEvent(_ event: EKEvent) {
    let eventTitle = event.title!
    if !event.hasNotes {
        NSLog("No notes for event (\(eventTitle))")
    }
    let meetLink = getMatch(text: (event.notes)!, regex: LinksRegex.meet)
    if let link = meetLink {
        let browserForMeetLinks = meetLinksBrowser(rawValue: UserDefaults.standard.integer(forKey: "browserForMeetLinks"))
        if browserForMeetLinks == .Chrome {
            openLinkInChrome(link)
        } else {
            openLinkInDefaultBrowser(link)
        }
    } else {
        NSLog("No meet link for event (\(eventTitle))")
        let zoomLink = getMatch(text: (event.notes)!, regex: LinksRegex.zoom)
        if let link = zoomLink {
            openLinkInDefaultBrowser(link)
        }
        NSLog("No zoom link for event (\(eventTitle))")
    }
}

func getCalendar(title: String, eventStore: EKEventStore) -> EKCalendar? {
    let calendars = eventStore.calendars(for: .event)
    for calendar in calendars {
        if calendar.title == title {
            return calendar
        }
    }
    return nil
}

func getMatch(text: String, regex: NSRegularExpression) -> String? {
    let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    let resultsMap = resultsIterator.map { String(text[Range($0.range, in: text)!]) }
    if !resultsMap.isEmpty {
        let meetLink = resultsMap[0]
        return meetLink
    }
    return nil
}

func openLinkInChrome(_ link: String) {
    let url = URL(string: link)!
    let configuration = NSWorkspace.OpenConfiguration()
    let chromeUrl = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    NSWorkspace.shared.open([url], withApplicationAt: chromeUrl, configuration: configuration, completionHandler: {
            _, _ in
            NSLog("Open \(url) in Chrome")
        })
}

func openLinkInDefaultBrowser(_ link: String) {
    let url = URL(string: link)!
    NSWorkspace.shared.open(url)
    NSLog("Open \(url) in default browser")
}

func cleanUpNotes(_ notes: String) -> String {
    let zoomSeparator = "\n──────────"
    let meetSeparator = "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"
    let cleanNotes = notes.components(separatedBy: zoomSeparator)[0].components(separatedBy: meetSeparator)[0]
    return cleanNotes
}

func eventStoreAccessCheck(eventStore: EKEventStore, completion: @escaping (AuthResult) -> Void) {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .authorized:
        completion(.success(true))
    case .denied, .notDetermined:
        eventStore.requestAccess(
            to: .event,
            completion:
                    { (granted: Bool, error: Error?) -> Void in
                    if error != nil {
                        completion(.failure(error!))
                    } else {
                        completion(.success(granted))
                    }
            })
    default:
        completion(.failure(NSError(domain: "Unknown authorization status", code: 0)))
    }
}