// macOS Native File Picker using NSOpenPanel
// Provides a proper native file picker that maintains window focus
#import <Cocoa/Cocoa.h>
#include <string.h>

// Show native macOS folder picker and return selected path
// Returns 0 on success, -1 on cancel/error
// NOTE: Must be called from main thread (GTK callbacks already run on main thread)
int macos_show_folder_picker(char* output_path, size_t max_len) {
    int result = -1;

    @autoreleasepool {
        NSOpenPanel* panel = [NSOpenPanel openPanel];

        // Configure for folder selection
        [panel setCanChooseFiles:NO];
        [panel setCanChooseDirectories:YES];
        [panel setAllowsMultipleSelection:NO];
        [panel setMessage:@"Select directory to scan"];
        [panel setPrompt:@"Select"];

        // Run modal - this properly maintains focus
        NSModalResponse response = [panel runModal];

        if (response == NSModalResponseOK) {
            NSURL* url = [[panel URLs] firstObject];
            if (url) {
                const char* path = [[url path] UTF8String];
                if (path && strlen(path) < max_len) {
                    strncpy(output_path, path, max_len - 1);
                    output_path[max_len - 1] = '\0';
                    result = 0;
                }
            }
        }
    }

    return result;
}
