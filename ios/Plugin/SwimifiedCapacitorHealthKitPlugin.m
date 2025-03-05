#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Define the plugin using the CAP_PLUGIN Macro, and
// each method the plugin supports using the CAP_PLUGIN_METHOD macro.
CAP_PLUGIN(SwimifiedCapacitorHealthKitPlugin, "SwimifiedCapacitorHealthKit",
           CAP_PLUGIN_METHOD(request_permissions, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(fetch_workouts, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(is_available, CAPPluginReturnPromise);
	   CAP_PLUGIN_METHOD(initialize_background_observer, CAPPluginReturnPromise);
)
