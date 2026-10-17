import AppKit

func launchWidget() {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        let controller = AppController()
        application.delegate = controller
        application.run()
    }
}

launchWidget()
