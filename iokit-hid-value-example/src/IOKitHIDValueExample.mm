@import CoreGraphics;

#import "IOKitHIDValueExample.h"
#include <pqrs/osx/iokit_hid_manager.hpp>
#include <pqrs/osx/iokit_hid_queue_value_monitor.hpp>
#include <pqrs/weakify.h>

@interface IOKitHIDValueExample ()

@property(weak) IBOutlet NSTextField* text;
@property NSMutableArray<NSString*>* eventStrings;
@property NSUInteger counter;
@property std::shared_ptr<pqrs::osx::iokit_hid_manager> hidManager;
@property std::shared_ptr<std::unordered_map<pqrs::osx::iokit_registry_entry_id, std::shared_ptr<pqrs::osx::iokit_hid_queue_value_monitor>>> monitors;

@end

@implementation IOKitHIDValueExample

- (void)initializeIOKitHIDValueExample {
  self.eventStrings = [NSMutableArray new];
  self.monitors = std::make_shared<std::unordered_map<pqrs::osx::iokit_registry_entry_id, std::shared_ptr<pqrs::osx::iokit_hid_queue_value_monitor>>>();

  std::vector<pqrs::cf::cf_ptr<CFDictionaryRef>> matching_dictionaries{
      pqrs::osx::iokit_hid_manager::make_matching_dictionary(
          pqrs::osx::iokit_hid_usage_page_generic_desktop,
          pqrs::osx::iokit_hid_usage_generic_desktop_keyboard),

      pqrs::osx::iokit_hid_manager::make_matching_dictionary(
          pqrs::osx::iokit_hid_usage_page_generic_desktop,
          pqrs::osx::iokit_hid_usage_generic_desktop_mouse),

      pqrs::osx::iokit_hid_manager::make_matching_dictionary(
          pqrs::osx::iokit_hid_usage_page_generic_desktop,
          pqrs::osx::iokit_hid_usage_generic_desktop_pointer),
  };

  self.hidManager = std::make_shared<pqrs::osx::iokit_hid_manager>(pqrs::dispatcher::extra::get_shared_dispatcher(),
                                                                   matching_dictionaries);
  self.hidManager->device_matched.connect([self](auto&& registry_entry_id, auto&& device_ptr) {
    if (device_ptr) {
      {
        auto d = pqrs::osx::iokit_hid_device(*device_ptr);

        [self updateEventStrings:@"device matched"];
        if (auto manufacturer = d.find_string_property(CFSTR(kIOHIDManufacturerKey))) {
          [self updateEventStrings:[NSString stringWithFormat:@"    manufacturer:%s", manufacturer->c_str()]];
        }
        if (auto product = d.find_string_property(CFSTR(kIOHIDProductKey))) {
          [self updateEventStrings:[NSString stringWithFormat:@"    product:%s", product->c_str()]];
        }
      }

      auto m = std::make_shared<pqrs::osx::iokit_hid_queue_value_monitor>(pqrs::dispatcher::extra::get_shared_dispatcher(),
                                                                          *device_ptr);
      (*self.monitors)[registry_entry_id] = m;

      m->started.connect([self, registry_entry_id] {
        [self updateEventStrings:[NSString stringWithFormat:@"started: %llu", type_safe::get(registry_entry_id)]];
      });

      m->stopped.connect([self, registry_entry_id] {
        [self updateEventStrings:[NSString stringWithFormat:@"stopped: %llu", type_safe::get(registry_entry_id)]];
      });

      m->values_arrived.connect([self](auto&& values) {
        for (const auto& value_ptr : *values) {
          if (auto e = IOHIDValueGetElement(*value_ptr)) {
            [self updateEventStrings:[NSString stringWithFormat:@"value: (UsagePage,Usage):(%ld,%ld) %ld",
                                                                static_cast<long>(IOHIDElementGetUsagePage(e)),
                                                                static_cast<long>(IOHIDElementGetUsage(e)),
                                                                static_cast<long>(IOHIDValueGetIntegerValue(*value_ptr))]];
          }
        }
      });

      m->error_occurred.connect([self](auto&& message, auto&& iokit_return) {
        [self updateEventStrings:[NSString stringWithFormat:@"error_occurred: %s", message.c_str()]];
      });

      m->async_start(kIOHIDOptionsTypeNone,
                     std::chrono::milliseconds(3000));
    }
  });

  self.hidManager->device_terminated.connect([self](auto&& registry_entry_id) {
    [self updateEventStrings:[NSString stringWithFormat:@"device terminated: %llu", type_safe::get(registry_entry_id)]];
    self.monitors->erase(registry_entry_id);
  });

  self.hidManager->error_occurred.connect([self](auto&& message, auto&& iokit_return) {
    [self updateEventStrings:[NSString stringWithFormat:@"error_occurred: %s", message.c_str()]];
  });

  self.hidManager->async_start();
}

- (void)terminateIOKitHIDValueExample {
  self.monitors->clear();
  self.hidManager = nullptr;
}

- (void)updateEventStrings:(NSString*)string {
  @weakify(self);
  dispatch_async(
      dispatch_get_main_queue(),
      ^{
        @strongify(self);
        if (!self) {
          return;
        }

        self.counter += 1;

        [self.eventStrings addObject:[NSString stringWithFormat:@"%06ld    %@", self.counter, string]];

        while (self.eventStrings.count > 16) {
          [self.eventStrings removeObjectAtIndex:0];
        }

        self.text.stringValue = [self.eventStrings componentsJoinedByString:@"\n"];
      });
}

@end
