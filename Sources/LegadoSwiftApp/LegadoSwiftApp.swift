import SwiftUI
import LegadoSwiftCore

@main
struct LegadoSwiftApp: App {
    @State private var sourceManager = BookSourceManager()
    @State private var bookManager = BookManager()
    @State private var readingConfig = ReadingConfig()

    var body: some Scene {
        let _ = bookManager.sourceManager = sourceManager
        WindowGroup {
            ContentView()
                .environment(sourceManager)
                .environment(bookManager)
                .environment(readingConfig)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件...") {
                    // Handled by bookshelf view
                }
                .keyboardShortcut("o")
            }
        }
    }
}
