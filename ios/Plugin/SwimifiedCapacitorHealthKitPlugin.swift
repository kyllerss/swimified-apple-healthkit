import Foundation
import Capacitor
import HealthKit
import CoreLocation
import os

/*

************************
* IMPLEMENTATION NOTES *
************************

The following are implementation notes that explain the important parts of background function definition for Apple HealthKit (AHK) that are not detailed very clearly in Apple's documentation.
 
NOTE: This is not meant to be a how-to on how to use this unpublished plugin. Use these notes to better understand how the code is structured and, more importantly, how you can implement your own version of this plugin to suit your needs. IOW, treat this as education material, nothing more.
 
Generally speaking, this plugin addresses the need of the Swimerize app to detect and handle new swims that have been added to AHK. This plugin registers an HKObserver query that listens for new swims and handles them by uploading them to a target API endpoint controlled by the Swimerize app for processing.
  
1. INITIAL SETUP
----------------

 The app (based on my tests) needs to be configured to enable AHK background processing. This can be done in XCode under the AHK entitlements.
 
 Further capabilities that I enabled are the following Background Modes: processing and fetch.
 
2. APP DELEGATE CHANGES/EXPECTATIONS
------------------------------------
 
 The AppDelegate needs to implement the following method for this plugin's background processing to work under certain scenarios. I will go more into detail later on, but you will need to implement the following methods in AppDelegate:
 
 ```
 import SwimifiedAppleHealthkit
 func application_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandle: @escaping () -> Void {
 
    BackgroundUploaderDelegate.shared.background_upload_completion = completionHandler
 }
 ```
 
 The code above is used exclusively for use-cases where an upload was not completed by iOS at the time it was originally scheduled and was resumed at a later point in time by iOS. This code above is called by iOS when it has decided to resume an upload. If you leave it out, usecases that will fail are those where AHK sync happens when network is not available (eg. Airplane Mode or if an upload takes longer than 30 seconds).
 
3. GENERAL PLUGIN LIFECYCLE
---------------------------
 
 This plugin's general usage lifecycle is as follows. Details on each step will be elaborated on later on.
 a. User authorizes access to AHK (function `request_permissions()`).
 b. UI invokes function `initialize_background_observer(opts: {upload_url: String, upload_token: String, start_date: Date})` to set upload properties (ie. server endpoint, and upload token) and the initial start date from which it will sync once the first callback occurs (typically set this to now). This function performs the following:
    1. Enables background delivery through a call to `healthStore.enableBackgroundDelivery`.
    2. Registers an HKQbserver callback query (NOTE: this step will actually run the listener query, so at this point it will look for and upload any swims that it detected in AHK based on the start_date parameter that was used when calling the initialize_background_observer function.
 c. (Optional) the UI invokes function `sync_workouts(opts: {start_date})` with a sync start date (eg. 1 year ago, 1 month ago, now) to explicitly upload a predetermined set of swims matchig a certain range. In the case of the Swimerize app, I initialize AHK (step (b)) with a date of `now`, and I call `sync_workouts` function with dates in the past to pull in historic swims and update the UI accordingly. This step is optional and you could very well simply call step (b) with a date in the past and upload those activities accordingly.
 
3. HKOBSERVERQUERY
------------------
 
 AHK implements the concept of a background notification listener through an HKObserverQuery. These queries are registered at startup (see function `load()` - which is called every time the plugin is initialized) and will be 'remembered' by AHK. AKH will invoke the corresponding continuation regardless of whether or not the app is runnig, backgrounded, or shut down each time it detects a change in AHK. The only role these queries have are to invoke the continuation with which they were created whenever new activity matching the provided criteria is detected. It is the responsibility of the registered observer query continuation to actually fetch contents from AHK for upload and process them.
 
 When a new activity triggers an HKObserver query callback, this plugin will fetch the latest swims by explicitly querying AHK using the latest recorded start date (this start_date data is updated after every successful upload completion). You will see that the implementation uses a start date instead of an anchor object when querying for changes since the last HKObserver query callback. This is due to some mysterious behaviour I encountered when first testing a purely anchor-based query implementation. My testing showed that anchor queries under undocumented circumstances won't 'advance'. This was sometimes unpredictable and resulted in duplicate uploads. Since I was tracking a start date for the activities separately, and in Swimerize's case, the swims added are typically single daily swims, I did not feel the need to use anchors.
 
 4. ASYNCHRONOUS UPLOAD
 ----------------------
 
 When it comes to uploading AHK data to an endpoint when the app is 'woken up' by AHK, there are a number of execution time restrictions. For one, all querying, processing, and upload execution time must fit within 30 seconds. As this plugin is not processing these results locally but instead relying on server-side logic to process these swims, this execution window will only be impacted by slow network uploads. Depending on the size of the data being uploaded, it is possible that the upload time exceeds these 30 seconds. As such, this plugin relies on iOS's UploadTask to 'hand-off' the upload to iOS. iOS will upload the payload on its own at a future point in time. The 30 second execution time does not apply to these background upload tasks. These upload tasks also have other benefits such as partial upload resume, retries in the event of network issues, etc...
 
 The following explains the execution flow for these background upload tasks:
 1. Happy path: When a user has good network connectivity, the execution flow is straight forward: The upload task is created, and iOS will attempt to upload the payload immediately. Upon successful completion of the upload, it will call the `BackgroundUploadDelegate.urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)` function for each upload task created. No other lifecycle calls transpire.
 2. Network unavailability: When user has placed the phone in Airplane Mode (or presumably if there is no network connectivity), the upload task will not execute but rather be scheduled and remain in a task queue until the network becomes available.  Once the network becomes available and the upload has completed successfully, the AppDelegate function `application(_ application: UIApplication, handleEentsForBackgroundURLSession identifier: String, completionHandler...` is invoked. This function is only meant to record this completionHandler reference. This completionHandler will be used by the next step - however, this completioHandler's only purpose is to signal to iOS that app has successfully processed the response of the upload task. As such, this function initializes the `BackgroundUploaderDelegate.shared.background_upload_completion` reference with this completionHandler.
 
  Once the completionHandler has been recorded, iOS will follow this call with a call to the `BackgroundUploaderDelegate.urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)`. This is the place where all internal state of the plugin needs to be handled for the successful upload (in this case, updating the start_date that will be used by the next sync event). Note, this function is called once per completed task, so if there were multiple queued tasks, this function will be called multiple times.
 
  Finally once all tasks have been processed by the above step, iOS will invoke `BackgroundUploaderDelegate.URLSessionDidFinishEvents(forBackgroundURLSession session: URLSession)` which is where we need to finalize processing by calling the previously-recorded completionHandler (ie. BackgroundUploaderDelegate.shared.background_upload_completion).
 
  3. Network upload exceeds 30s: If the upload takes longer than 30 seconds due to the size of the data or network slowdowns, iOS will handle it in the same way as it handled scenario #2 above.
  4. Network error: In the event that there is a network error, iOS will automatically retry the upload. No handling is necessary or possible. Once the upload succeeds, the same lifecycle calls will happen as those in scenario #2. As a side note, if there is a server-end error and a non-2xx http response status, the code in `BackgroundUploaderDelegate.urlSession` is responsible for rescheduling the upload. In this plugin's case, the start_date state is not updated and we rely on future app initializations or other AHK events to sync the ommitted upload.
 
 SIDE NOTE: You will notice that the UserDefaults are executing in the MainActor thread. This is apparently a requirement by UserDefaults. There is no guarantee that the thread handling AHK observer events will be handled by the main thread, so all code dealing with updating the upload state explicitly is run in a MainActor thread.
 
*/

func log(_ message: String) {
    
    os_log("SwimifiedCapacitorHealthKitPlugin: %{public}@", log: OSLog.default, type: .debug, message)
}

var healthStore = HKHealthStore()
var is_observer_active = false

public class BackgroundUploaderDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    
    public static let shared = BackgroundUploaderDelegate()
    
    public var url_session: URLSession!
    public var background_upload_completion: (() -> Void)?

    override init() {

        super.init()
        
//        log("BackgroundUploadDelegate constructor called!")
                
        /*
         * Always make sure that the url session delegate is available
         */
        let config = URLSessionConfiguration.background(withIdentifier: "com.swimified.workout_upload")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        
//        log("URL Session being constructed with delegate: \(type(of: self))")
        
        self.url_session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        
//        log("urlSessionDidFinishEvents! \(String(describing: session.configuration.identifier)) \(self.background_upload_completion == nil)")

        // signal to iOS that processing complete
        self.background_upload_completion?()
        self.background_upload_completion = nil
    }
    
    /*
     * Called each time an upload task has completed.
     */
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    
//        log("urlSession didCompleteWithError called. Error present? \(error != nil)")
        if let error = error {
            
            log("Error completing upload: \(error)")
            return
        }
        
        guard let http_response = task.response as? HTTPURLResponse else {
            
            log("Task completed, but response is not an HTTPURLResponse")
            return
        }

//        log("Checking response status code: \(http_response.statusCode)")
        let success_response = (200...299).contains(http_response.statusCode)
//        log("Calculated success response? \(success_response)")
        if success_response {
            
            log("Task complete with successful status code of \(http_response.statusCode)")
            
        } else {
            
            log("Task failed with status code: \(http_response.statusCode)")
            return
        }
        
        DispatchQueue.main.async {
            
            let latest_start_date = SwimifiedCapacitorHealthKitPlugin._retrieve_pending_upload_state()

            guard let start_date = latest_start_date else {
                
                log("Pending upload state previously cleared, aborting...")
                return
            }
            
//            log("Retrieved pending upload state: \(String(describing: latest_start_date))")
                            
            // record successful completion (update latest sync start date)
            if let start_date = latest_start_date {
                
//                log("Persisting latest start date: \(start_date)")
                SwimifiedCapacitorHealthKitPlugin._store_start_date(start_date: start_date)
                
            } else {
                
                log("WARNING! Lastest start date from UserDefaults not present.")
            }
            
//            log("post_workout_completion is nil? \(self.background_upload_completion == nil)")
            
            SwimifiedCapacitorHealthKitPlugin._clear_pending_upload_state()
            
//            log("Finished clearing pending upload state.")
                
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        
        log("didSendBodyData \(bytesSent)")
    }
}

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(SwimifiedCapacitorHealthKitPlugin)
public class SwimifiedCapacitorHealthKitPlugin: CAPPlugin {
    
    enum HKSampleError: Error {
        
        case workoutRouteRequestFailed
    }
            
    @MainActor
    public override func load() {
        
//        log("Lifecycle method load() called on HealthKit plugin.")
        
        super.load()

        guard #available(iOS 15.0, *) else {
            log("Apple HealthKit not available on this iOS version - skipping")
            return
        }

        /*
         * Only activate the background observer if AHK has been authorized.
         *
         * NOTE: Initially the call here was for is_authorized(),
         * but AHK does not support determining if a user authorized
         * 'read' access to AHK (only 'write' access). As such,
         * the only option is to check to see if any of the manually-
         * maintained execution state is present to determine if
         * the user ever authorized AHK.
         */
        let authorized = self._is_authorized()
        if authorized {
            log("load() starting background observer")
            self._start_background_workout_observer()
        } else {
            log("HealthKit not authorized - skipping starting observer query.")
        }
    }

    @MainActor
    public static func _store_start_date(start_date: Date?) {
        
        if start_date == nil {
            
            UserDefaults.standard.removeObject(forKey: "upload_start_date")
            log("Removed upload_start_date from UserDefaults")
            return
        }

        UserDefaults.standard.set(start_date, forKey: "upload_start_date")
        log("Stored start_date in UserDefaults: \(String(describing: start_date))")
    }
    
    @MainActor
    private func _retrieve_start_date() -> Date? {
        return UserDefaults.standard.object(forKey: "upload_start_date") as? Date
    }
        
    @MainActor
    func _update_upload_properties(upload_target_url: String, upload_token: String, upload_start_date: Date?) {
        
//        log("Updating upload properties: \(upload_target_url), \(upload_token), \(String(describing: upload_start_date))")
        // persist upload properties
        UserDefaults.standard.set(upload_target_url, forKey: "upload_target_url")
        UserDefaults.standard.set(upload_token, forKey: "upload_token")
        
        /*
         * Important to only update, never clear the start_date.
         * This function is used for initial registration (start_date is provided)
         * and for updating upload tokens (start_date is not provided).
         */
        if let start_date = upload_start_date {
            
            SwimifiedCapacitorHealthKitPlugin._store_start_date(start_date: start_date)
//            log("Stored start_date in UserDefaults: \(start_date)")
        }
    }
    
    @MainActor @objc func update_upload_properties(_ call: CAPPluginCall) {
                
        guard let upload_target_url = call.getString("upload_url") else {
            return call.reject("Parameter upload_url is required.")
        }
        
        guard let upload_token = call.getString("upload_token") else {
            return call.reject("Parameter upload_token is required.")
        }

        _update_upload_properties(upload_target_url: upload_target_url, upload_token: upload_token, upload_start_date: nil)
            
        return call.resolve()
    }
    
    @available(iOS 15.0, *)
    @MainActor @objc func initialize_background_observer(_ call: CAPPluginCall) {
        
        guard let start_date = call.getDate("start_date") else {
            return call.reject("Parameter start_date is required.")
        }
        
        guard let upload_target_url = call.getString("upload_url") else {
            return call.reject("Parameter upload_url is required.")
        }
        
        guard let upload_token = call.getString("upload_token") else {
            return call.reject("Parameter upload_token is required.")
        }
        
//        log("initialize_background_observer called from JS context: \(start_date), \(upload_token)")
        
        // persist upload properties
        _update_upload_properties(upload_target_url: upload_target_url, upload_token: upload_token, upload_start_date: start_date)

        /*
         * When this is first ever initialized (eg. during authorization process)
         * then we need to establish a starting point (ie. start_date). This applies
         * only to background sync callbacks for new workouts moving forward from the
         * specified start_date.
         *
         * Any workouts that exist prior to that start_date are to be manually sync'ed by
         * the app, which will give users the ability of controlling which
         * workouts to include/exclude.
         */
//        log("initialize_background_observer initializing start_date: \(start_date)")
        SwimifiedCapacitorHealthKitPlugin._store_start_date(start_date: start_date)

        _start_background_workout_observer() // initalizes anchor query and observer
                    
        call.resolve(["authorized": true])
    }
        
    @MainActor
    private func _retrieve_upload_endpoint_properties() -> (upload_url: String, upload_token: String) {
        
        let upload_url = UserDefaults.standard.string(forKey: "upload_target_url") ?? "https://www.swimerize.com/integrations/apple/inbound/sync/activity"
        let upload_token = UserDefaults.standard.string(forKey: "upload_token") ?? "<MISSING TOKEN>"

        return (upload_url: upload_url, upload_token: upload_token)
    }
    
    @available(iOS 15.0, *)
    @MainActor
    private func _sync(start_date: Date?, end_date: Date?, caller_id: String) async -> Bool {
        
//        log("_sync: querying for workouts w/ \(String(describing: start_date)) and \(String(describing: end_date))")

        var effective_start_date = start_date
        var effective_end_date = end_date
        if (start_date != nil && end_date != nil) {
            
            let reordered_dates = _reorder_dates(start: start_date!, end: end_date!)
            effective_start_date = reordered_dates.start
            effective_end_date = reordered_dates.end
        }

        let upload_properties = self._retrieve_upload_endpoint_properties()
        let upload_url = upload_properties.upload_url
        let upload_token = upload_properties.upload_token
        
        // iterate through batches performing an upload
        var current_anchor: HKQueryAnchor? = nil
        while true {
        
            let (workouts, latest_start_date, new_anchor) = await self._internal_fetch_workouts(start_date: effective_start_date, end_date: effective_end_date, anchor: current_anchor, caller_id: caller_id, limit: 25)
            current_anchor = new_anchor

            if workouts.isEmpty {
//                log("Sync Workouts: No workouts left.")
                break
            }
            
//            log("Sync Workouts: Fetched \(workouts.count) workouts")
                                            
//            log("-----> Sync-posting to \(upload_url) w/ token \(upload_token)")
                                    
            let latest_sync_start_date = latest_start_date ?? Date()
            let post_scheduled = await self._post_workout(workouts, upload_url: upload_url, upload_token: upload_token, latest_sync_start_date: latest_sync_start_date)
            if post_scheduled == false {
                
                log("Error posting workouts to server. Exiting sync loop.")
                return false
            }
        }
                
        return true
    }
    
    /**
     * Assumes background anchor initialized.
     */
    @available(iOS 15.0, *)
    private func _start_background_workout_observer() {
        
        if is_observer_active {
            log("Function _start_background_workout_observer called while observer is already active.")
            return
        }
        
//        log("Function _start_background_workout_observer called.")
         
        let workoutType = HKObjectType.workoutType()
        
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) {success, error in
        
            if let error = error {
                log("(healthStore.enableBackgroundDelivery) Failed to enable background delivery: \(error.localizedDescription)")
                
                return
                
            } else {
                log("(healthStore.enableBackgroundDelivery) Background delivery enabled: \(success)")
            }
        }
        
        let observerQuery = HKObserverQuery(sampleType: workoutType, predicate: nil) {
            
            [weak self] _, completionHandler, error in
            guard let self = self else {
                log("HKObserverQuery reference to 'self' is nil!")
                return
            }
            
//            log("------> Observer query invoked!")
            
            if let error = error {
                
                log("Observer query error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            Task {
                
                let start_date: Date? = await self._retrieve_start_date()
                if start_date != nil {

                    let success = await self._sync(start_date: start_date, end_date: nil, caller_id: "_start_background_workout_observer")
                    log("Completed processing latest changes: Success? \(success)")
                    
                } else {
                    
                    log("Start date missing, skipping initial query.")
                }
                
                completionHandler()
            }
        }
        
        healthStore.execute(observerQuery)
        
        is_observer_active = true
//        log("------> Observer query registered!")

    }
    
    /**
     * Capacitor performs a similar operation on the returned [JSObject] results.
     * To preserve the existing flow, we perform a similar operation on the result
     * set before performing the POST operation as serializing to JSON an object
     * that has Date objects causes serialization errors.
     */
    private func _prepare_for_serialization(in object: Any) -> Any {
        
        if let date = object as? Date {
            return ISO8601DateFormatter().string(from: date)
        } else if let array = object as? [Any] {
            return array.map { _prepare_for_serialization(in: $0) }
        } else if let dictionary = object as? [String: Any] {
            var converted = [String: Any]()
            for (key, value) in dictionary {
                converted[key] = _prepare_for_serialization(in: value)
            }
            return converted
        }
        return object
    }

    private func _store_pending_upload_state(latest_start_date: Date) {
        
        UserDefaults.standard.set(latest_start_date, forKey: "latest_start_date")
    }
    
    public static func _retrieve_pending_upload_state() -> Date? {
        
        let latest_start_date = UserDefaults.standard.object(forKey: "latest_start_date") as? Date
        return latest_start_date
    }
    
    public static func _clear_pending_upload_state() {
        
        UserDefaults.standard.removeObject(forKey: "latest_start_date")
    }
    
//    @MainActor
    @available(iOS 15.0, *)
    private func _post_workout(_ workouts: [JSObject], upload_url: String, upload_token: String, latest_sync_start_date: Date) async -> Bool {
        
//        log("--------> Posting workout")
                        
        guard let url = URL(string: upload_url) else {
            log("Unable to determine POST url endpoint: \(upload_url)")
            return false
        }
                
        /*
         * Serialize JSON
         */
        var payload_json = JSObject()
        payload_json["workout_results"] = workouts
        payload_json["upload_token"] = upload_token
                
        let serializable_results = self._prepare_for_serialization(in: payload_json)
        guard let json_data = try? JSONSerialization.data(withJSONObject: serializable_results) else {
            
            log("Error serializing workout for POST")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

//        log("Calling url_session...")

        // create upload file
        let tmp_dir = FileManager.default.temporaryDirectory
        let tmp_file_url = tmp_dir.appendingPathComponent("tmp_workout_payload.json")
        do {
            
            try json_data.write(to: tmp_file_url)
            
        } catch {
            
            log("Unable to write tmp upload file: \(error)")
            return false // no completion callback
        }
             
        self._store_pending_upload_state(latest_start_date: latest_sync_start_date)

        let upload_task = BackgroundUploaderDelegate.shared.url_session.uploadTask(with: request, fromFile: tmp_file_url)
        upload_task.resume()
            
//        log("Post workout request sent/scheduled.")
        return true
    }
    
    private func _reorder_dates(start: Date, end: Date) -> (start: Date, end: Date) {
        
        var startDate = start
        var endDate = end
        
        if startDate > endDate {
            
            swap(&startDate, &endDate)
        }
        
        if startDate == endDate {
            
            endDate = endDate.addingTimeInterval(1)
        }
        
        return (startDate, endDate)
    }
    
    @objc func is_available(_ call: CAPPluginCall) {
        
        if #available(iOS 16.0, *) {
            
            if HKHealthStore.isHealthDataAvailable() {
                return call.resolve()
            } else {
                return call.reject("Apple HealthKit is not available on this device.")
            }
            
        } else {
            
            // iOS >=16 supported
            return call.reject("Apple HealthKit support is limited to iOS 16 and above.")
        }
    }
    
    @MainActor private func _is_authorized() -> Bool {
                
        return self._retrieve_start_date() != nil
    }
    
    @MainActor @objc func is_authorized(_ call: CAPPluginCall) {
     
        let authorized = self._is_authorized()
        
        call.resolve(["authorized": authorized])
    }

    @MainActor @objc func sync_workouts(_ call: CAPPluginCall) {
     
        let start_date = call.getDate("start_date")
        let end_date = call.getDate("end_date")
        
        guard #available(iOS 15.4, *) else {
            log("Unsupported iOS version, aborting sync_workouts")
            call.resolve()
            return
        }

        Task {
            
            let success = await self._sync(start_date: start_date, end_date: end_date, caller_id: "sync_workouts")
            
//            log("Sync workouts success?: \(success)")
            
            call.resolve()
        }
    }

    @objc public func request_permissions(_ call: CAPPluginCall) {
        
        if !HKHealthStore.isHealthDataAvailable() {
            return call.reject("Apple HealthKit is not available on this device.")
        }
        
        let writeTypes: Set<HKSampleType> = []
        var readTypes: Set<HKSampleType> = [
            HKWorkoutType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        
        if let hr_type = HKQuantityType.quantityType(forIdentifier:
            .heartRate) {
            
            readTypes.insert(hr_type)
        }
        
        if let sc_type = HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount) {
            
            readTypes.insert(sc_type)
        }
        
        if let vo2Max_type = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            
            readTypes.insert(vo2Max_type)
        }
                                                
        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, _ in
            
            if !success {
                call.reject("Unable to get needed HealthKit permissions.")
                return
            }
            
            call.resolve()
        }
        
        return;
    }
    
//    private func is_anchor_equal(anchor: HKQueryAnchor?, new_anchor: HKQueryAnchor?) -> Bool {
//        
//        if let unwrapped_anchor = anchor, let unwrapped_new_anchor = new_anchor {
//            
//            if unwrapped_anchor.isEqual(unwrapped_new_anchor) {
//                log("Anchors are EQUAL: \(String(describing: anchor)) & \(String(describing: new_anchor))")
//                return true
//            } else {
//                log("Anchors are NOT EQUAL: \(String(describing: anchor)) & \(String(describing: new_anchor))")
//                return false
//            }
//            
//        } else if anchor == nil && new_anchor == nil {
//            
//            log("Anchors are both nil!")
//            return true;
//        } else {
//            
//            log("One of the anchors is nil! \(String(describing: anchor)) \(String(describing: new_anchor))")
//            return false
//        }
//    }
    
    private func _internal_fetch_workouts(start_date: Date?, end_date: Date?, anchor: HKQueryAnchor?, caller_id: String, limit: Int) async -> ([JSObject], Date?, HKQueryAnchor?) {
    
//        log("----> \(caller_id) => _internal_fetch_workouts... start: \(String(describing: start_date)), end: \(String(describing: end_date))");
        
        guard #available(iOS 15.4, *) else {
            return ([], nil, nil)
        }
                                
//        log("Initializing predicate for _internal_fetch_workouts...")
            
        /*
         * Predicate creation: creates a 'workout type' compound predicate (OR logic) and applies that to a date-based predicate (AND)
         */
        var workout_types: [HKWorkoutActivityType] = [.swimming]
        if #available(iOS 16.0, *) {
            workout_types.append(.swimBikeRun)
        }
        let workout_predicates = workout_types.map {HKQuery.predicateForWorkouts(with: $0)}
        let compound_workout_predicates = NSCompoundPredicate(orPredicateWithSubpredicates: workout_predicates)
        
        var effective_end_date = end_date
        if (effective_end_date == nil) {
            effective_end_date = Date()
        }

        let date_predicate = HKQuery.predicateForSamples(withStart: start_date, end: effective_end_date, options: .strictStartDate)
        
        let unified_predicates = NSCompoundPredicate(andPredicateWithSubpredicates: [compound_workout_predicates, date_predicate])
        let predicates = [HKSamplePredicate.workout(unified_predicates)]
        
        /*
         * Query invocation
         */
        let query = HKAnchoredObjectQueryDescriptor(predicates: predicates, anchor: anchor, limit: limit)

        var query_results: HKAnchoredObjectQueryDescriptor<HKWorkout>.Result
        do {
            query_results = try await query.result(for: healthStore)
        } catch {
            
            log("Unable to query healthStore for workouts: \(error.localizedDescription)")
            return ([], nil, nil)
        }
            
        /*
         * Results processing
         */
        let workouts = query_results.addedSamples as [HKWorkout]
        let current_anchor = query_results.newAnchor

        if workouts.isEmpty {
            
//            log("\(caller_id) _internal_fetch_workouts: No workouts found")
            return ([], nil, current_anchor)
        }

        let to_return = await self.generate_sample_output(results: workouts) ?? []
            
        // obtain the latest start date
        // let latest_start_date = workouts.last?.startDate
        let latest_start_date = workouts.max {$0.endDate < $1.endDate }?.endDate
        let first_end_date = workouts.first?.endDate
        let latest_end_date = workouts.last?.endDate
//        log("======> first and last sanity check: \(String(describing: first_end_date)) and \(String(describing: latest_end_date))")
        
//        log("\(caller_id) _internal_fetch_workouts: \(to_return.count) workouts found => latest_start_date: \(String(describing: latest_start_date))")
        
        return (to_return, latest_start_date, current_anchor)
    }
    
    @objc func fetch_workouts(_ call: CAPPluginCall) {
        
        guard var startDate = call.getDate("start_date") else {
            return call.reject("Parameter start_date is required!")
        }
        guard var endDate = call.getDate("end_date") else {
            return call.reject("Parameter end_date is required!")
        }
        
        let reordered_dates = _reorder_dates(start: startDate, end: endDate)
        startDate = reordered_dates.start
        endDate = reordered_dates.end

        Task {
            
            let (workout_results, _, _) = await _internal_fetch_workouts(start_date: startDate, end_date: endDate, anchor: nil, caller_id: "fetch_workouts", limit: HKObjectQueryNoLimit)
            
            call.resolve([
                "count": workout_results.count,
                "results": workout_results
            ])
        }
    }
    
    func generate_sample_output(results: [HKSample]?) async -> [JSObject]? {
        
        guard let results = results else {
            return []
        }

        var output: [JSObject] = []

        for result in results {

            guard let sample = result as? HKWorkout else {
                continue
            }

            // only process swim-related activities
            if #available(iOS 16.0, *) {
                if sample.workoutActivityType != HKWorkoutActivityType.swimming
                    && sample.workoutActivityType != HKWorkoutActivityType.swimBikeRun {
                    continue
                }
            } else {
                // Fallback on earlier versions
                if sample.workoutActivityType != HKWorkoutActivityType.swimming {
                    continue
                }
            }
            
            var workout_obj = JSObject()
            workout_obj["uuid"] = sample.uuid.uuidString
            workout_obj["start_date"] = sample.startDate
            workout_obj["end_date"] = sample.endDate
            workout_obj["source"] = sample.sourceRevision.source.name
            workout_obj["source_bundle_id"] = sample.sourceRevision.source.bundleIdentifier
            workout_obj["device"] = _get_device_information(device: sample.device)
            workout_obj["HKWorkoutActivityTypeId"] = Int(sample.workoutActivityType.rawValue)

            // process stroke count data
            let stroke_count_data: [JSObject]
            do {
                stroke_count_data = try await _get_stroke_count_data(sample)
            } catch {
                stroke_count_data = []
            }

            let vo2max_data: [JSObject]
            do {
                vo2max_data = try await _get_vo2max_data(sample)
            } catch {
                vo2max_data = []
            }

            /*
             * NOTE: In case of a simple swim, there is one entry.
             *       In case of triathlon, multiple entries of which one is a swim.
             */
            var activities_obj: [JSObject] = []
            if #available(iOS 16.0, *) {
                
                for activity in sample.workoutActivities {
                    
                    let workout_config = activity.workoutConfiguration
                    
                    let lap_length = workout_config.lapLength
                    let location_type = workout_config.swimmingLocationType
                    var start_date = activity.startDate
                    guard var end_date = activity.endDate else {
                        
                        // empty end_date implies still active or interrupted activity - skip
                        continue
                    }
                    let uuid = activity.uuid
                                        
                    let reordered_dates = _reorder_dates(start: start_date, end: end_date)
                    start_date = reordered_dates.start
                    end_date = reordered_dates.end

                    // events
                    var events: [JSObject] = []
                    for event in activity.workoutEvents {
                        
                        events.append(_generate_event_output(event: event))
                    }
                    
                    // heart rate data
                    let heart_rate_data: [JSObject]
                    do {
                        heart_rate_data = try await _get_heart_rate(start_date: start_date, end_date: end_date, workout: sample)
                    } catch {
                        heart_rate_data = []
                    }
                    
                    // workout data
                    var js_obj = JSObject()
                    
                    js_obj["uuid"] = uuid.uuidString
                    js_obj["start_date"] = start_date
                    js_obj["end_date"] = end_date
                    js_obj["HKWorkoutEvents"] = events
                    js_obj["HKLapLength"] = lap_length?.doubleValue(for: .meter())
                    js_obj["HKSwimLocationType"] = location_type.rawValue
                    js_obj["HKWorkoutActivityType"] = Int(workout_config.activityType.rawValue)
                    js_obj["heart_rate_data"] = heart_rate_data
                    js_obj["stroke_count_data"] = stroke_count_data
                    js_obj["vo2max_data"] = vo2max_data
                    
                    activities_obj.append(js_obj)
                }
                
            } else {
                return nil // signals an error to be sent to client
            }

            workout_obj["HKWorkoutActivities"] = activities_obj
            
            // GPS coordinates
            do {
                let route: HKWorkoutRoute = try await _get_route(for: sample)
                let locations = try await _get_locations(for: route)
                
                var cl_locations: [JSObject] = []
                for location in locations {
                    
                    cl_locations.append(_generate_location_output(from: location))
                }
                
                workout_obj["CLLocations"] = cl_locations

            } catch {
                log("Unable to process CLLocations for \(sample.uuid.uuidString) \(error)")
            }

            output.append(workout_obj)
        }
        
        return output
     }
    
    private func _get_stroke_count_data(_ workout: HKWorkout) async throws -> [JSObject] {
        try await withCheckedThrowingContinuation { continuation in
            _get_stroke_count(for: workout) { result in
                continuation.resume(with: result)
            }
        }
    } 
    private func _get_stroke_count(for workout: HKWorkout, completion: @escaping (Result<[JSObject], Error>) -> Void) {
        
        var to_return: [JSObject] = []
        var start_date = workout.startDate;
        var end_date = workout.endDate;
        
        let reordered_dates = _reorder_dates(start: start_date, end: end_date)
        start_date = reordered_dates.start
        end_date = reordered_dates.end

        let predicate = HKQuery.predicateForSamples(withStart: start_date, end: end_date, options: .strictStartDate)
        
        guard let stroke_count_type = HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount) else {
        
            return completion(.success([])) // stroke count not supported
        }
        
        let query = HKSampleQuery(sampleType: stroke_count_type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in
        
            if let error = error {
                
                return completion(.failure(error))
            }
            
            guard let stroke_count_samples = samples as? [HKQuantitySample] else {

                let castError = NSError(
                    domain: "com.swimified.capacitor.healthkit",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey : "Could not cast stroke count samples to [HKQuantitySample]"]
                )
                
                return completion(.failure(castError))
            }
                            
            for sample in stroke_count_samples {
                
                let value = sample.quantity.doubleValue(for: HKUnit.count())
                let start_time = sample.startDate
                let end_time = sample.endDate

                var json_object = JSObject()
                json_object["count"] = value
                json_object["start_time"] = start_time
                json_object["end_time"] = end_time
                                
                to_return.append(json_object)
            }
            
            return completion(.success(to_return))
        }
        
        healthStore.execute(query)
    }

    private func _get_vo2max_data(_ workout: HKWorkout) async throws -> [JSObject] {
        try await withCheckedThrowingContinuation { continuation in
            _get_vo2max(for: workout) { result in
                continuation.resume(with: result)
            }
        }
    }
    private func _get_vo2max(for workout: HKWorkout, completion: @escaping (Result<[JSObject], Error>) -> Void) {
        
        var to_return: [JSObject] = []
        var start_date = workout.startDate;
        var end_date = workout.endDate;

        let reordered_dates = _reorder_dates(start: start_date, end: end_date)
        start_date = reordered_dates.start
        end_date = reordered_dates.end

        let predicate = HKQuery.predicateForSamples(withStart: start_date, end: end_date, options: .strictStartDate)
        
        guard let vo2max_type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else {
            
            return completion(.success([])) // vo2max not supported
        }
        
        let query = HKSampleQuery(sampleType: vo2max_type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in
        
            if let error = error {
                
                return completion(.failure(error))
            }
            
            guard let vo2max_samples = samples as? [HKQuantitySample] else {

                let castError = NSError(
                    domain: "com.swimified.capacitor.healthkit",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey : "Could not cast vo2max samples to [HKQuantitySample]"]
                )
                
                return completion(.failure(castError))
            }
            
            for sample in vo2max_samples {
                                
                let unit = HKUnit(from: "ml/(kg*min)")
                let vo2max_value = sample.quantity.doubleValue(for: unit)
                let start_time = sample.startDate
                let end_time = sample.endDate

                var json_object = JSObject()
                json_object["vo2max_value"] = vo2max_value
                json_object["start_time"] = start_time
                json_object["end_time"] = end_time
                                
                to_return.append(json_object)
            }
            
            return completion(.success(to_return))
        }
        
        healthStore.execute(query)
    }
    
    @available(iOS 15.0, *)
    private func _get_heart_rate(start_date: Date, end_date: Date, workout: HKWorkout) async throws -> [JSObject] {
        try await withCheckedThrowingContinuation { continuation in
            _get_heart_rate(start_date: start_date, end_date: end_date, workout: workout) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    @available(iOS 15.0, *)
    private func _get_heart_rate(start_date: Date, end_date: Date, workout: HKWorkout, completion: @escaping (Result<[JSObject], Error>) -> Void) {
        
        let reordered_dates = _reorder_dates(start: start_date, end: end_date)
        let start_date = reordered_dates.start
        let end_date = reordered_dates.end

        guard let heart_rate_type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            
            return completion(.success([])) // hr not supported
        }
        
        let for_workout = HKQuery.predicateForSamples(withStart: start_date, end: end_date, options: HKQueryOptions.strictStartDate)
        let heart_rate_descriptor = HKQueryDescriptor(sampleType: heart_rate_type, predicate: for_workout)
                
        let query = HKSampleQuery(queryDescriptors: [heart_rate_descriptor], limit: HKObjectQueryNoLimit) { (query, samples, error) in
            
            if let resultError = error {
                return completion(.failure(resultError))
            }
            
            guard let samples = samples else {
                return completion(.success([])) // no results, return empty list
            }
            
            Task {
                
                var hr_entries: [JSObject] = []
                for sample in samples {
                        
                    guard let sample = sample as? HKDiscreteQuantitySample else {
                        continue // discard any unexpected types
                    }
                    
                    var series_data: [JSObject] = []
                    if (sample.count == 1) {

                        let bpm = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))

                        var js_obj = JSObject()
                        js_obj["start_date"] = sample.startDate
                        js_obj["end_date"] = sample.endDate
                        js_obj["motion_context"] = sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber
                        js_obj["heart_rate"] = bpm

                        series_data.append(js_obj)

                    } else {

                        // query series data
                        do {
                            
                            series_data = try await self._get_heart_rate_series_data(start_date: start_date, end_date: end_date, series_sample: sample)
                            
                        } catch {
                            series_data = []
                        }
                    }
                    
                    hr_entries.append(contentsOf: series_data)
                }
                
                completion(.success(hr_entries))
            }
        }
        
        healthStore.execute(query)
    }

    @available(iOS 15.0, *)
    private func _get_heart_rate_series_data(start_date: Date, end_date: Date, series_sample: HKDiscreteQuantitySample) async throws -> [JSObject] {
        try await withCheckedThrowingContinuation { continuation in
            _get_heart_rate_series_data(start_date: start_date, end_date: end_date, series_sample: series_sample) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    @available(iOS 15.0, *)
    private func _get_heart_rate_series_data(start_date: Date, end_date: Date, series_sample: HKDiscreteQuantitySample, completion: @escaping (Result<[JSObject], Error>) -> Void) {
        
        guard let heart_rate_type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
        
            return completion(.success([])) // hr not supported
        }
        
        let in_series_sample = HKQuery.predicateForObject(with: series_sample.uuid)
        var elements: [JSObject] = []
        let detail_query = HKQuantitySeriesSampleQuery(quantityType: heart_rate_type, predicate: in_series_sample)
        {query, quantity, dateInterval, HKSample, done, error in
                        
            if let resultError = error {
                log("Error when fetching hr series data: \(resultError)")
                return completion(.success(elements)) // return results so far
            }
                
            guard let quantity = quantity, let dateInterval = dateInterval else {

                if done {
                    completion(.success(elements))
                }
                return // next iteration (if any)
            }
            
            let bpm = quantity.doubleValue(for: HKUnit(from: "count/min"))
            
            var js_obj = JSObject()
            js_obj["start_date"] = dateInterval.start
            js_obj["end_date"] = dateInterval.end
            js_obj["heart_rate"] = bpm
            
            elements.append(js_obj)

            if done {
                completion(.success(elements))
            }
        }
        
        healthStore.execute(detail_query)
   }
    
    private func _generate_event_output(event: HKWorkoutEvent) -> JSObject {
        
        let type: HKWorkoutEventType = event.type
        let start_timestamp: Date = event.dateInterval.start
        let end_timestamp: Date = event.dateInterval.end
        let stroke_style = event.metadata?[HKMetadataKeySwimmingStrokeStyle] as? NSNumber

        var swolf: NSNumber?;
        if #available(iOS 16.0, *) {
            swolf = event.metadata?[HKMetadataKeySWOLFScore] as? NSNumber
        } else {
            swolf = nil
        }
        
        var to_return = JSObject()
        
        to_return["type"] = type.rawValue
        to_return["start_timestamp"] = start_timestamp
        to_return["end_timestamp"] = end_timestamp
        to_return["stroke_style"] = stroke_style
        to_return["swolf"] = swolf
        
        return to_return
    }
    
    private func _get_device_information(device: HKDevice?) -> JSObject? {
        
        if (device == nil) {
            return nil;
        }
                        
        var device_information = JSObject()
        device_information["name"] = device?.name
        device_information["model"] = device?.model
        device_information["manufacturer"] = device?.manufacturer
        device_information["hardware_version"] = device?.hardwareVersion
        device_information["software_version"] = device?.softwareVersion
        
        return device_information;
    }
    
    private func _get_route(for workout: HKWorkout) async throws -> HKWorkoutRoute {
        try await withCheckedThrowingContinuation { continuation in
            _get_route(for: workout) { result in
                continuation.resume(with: result)
            }
        }
    }
    private func _get_route(for workout: HKWorkout, completion: @escaping (Result<HKWorkoutRoute, Error>) -> Void) {
        
        let predicate = HKQuery.predicateForObjects(from: workout)
        let query = HKAnchoredObjectQuery(type: HKSeriesType.workoutRoute(),
                                          predicate: predicate,
                                          anchor: nil,
                                          limit: HKObjectQueryNoLimit)
        { _, samples, _, _, error in
            if let resultError = error {
                log("Error when fetching route: \(resultError)")
                return completion(.failure(resultError))
            }
            
            if let routes = samples as? [HKWorkoutRoute],
               let route = routes.first
            {
                return completion(.success(route))
            }
            
            return completion(.failure(HKSampleError.workoutRouteRequestFailed))
        }
        
        healthStore.execute(query)
    }

    private func _get_locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation{ continuation in
            _get_locations(for: route) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    private func _get_locations(for route: HKWorkoutRoute, completion: @escaping(Result<[CLLocation], Error>) -> Void) {
        var queryLocations = [CLLocation]()
        let query = HKWorkoutRouteQuery(route: route) { query, locations, done, error in

            if error != nil {
                return completion(.success(queryLocations)) // terminate w/ results so far
            }

            if let locationBatch = locations {
                queryLocations.append(contentsOf: locationBatch)
            }

            if done {
                completion(.success(queryLocations))
            }
        }
        
        healthStore.execute(query)
    }

    private func _generate_location_output(from location: CLLocation) -> JSObject {

        let timestamp: Date = location.timestamp
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let altitude = location.altitude
        
        var to_return = JSObject();
        to_return["timestamp"] = timestamp
        to_return["latitude"] = latitude
        to_return["longitude"] = longitude
        to_return["altitude"] = altitude
        
        return to_return
    }
}
