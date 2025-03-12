import Foundation
import Capacitor
import HealthKit
import CoreLocation
import os

func log(_ message: String) {
    
    os_log("SwimifiedCapacitorHealthKitPlugin: %{public}@", log: OSLog.default, type: .debug, message)
}

//URLSessionDelegate, URLSessionTaskDelegate {
    
class UploadWorkoutDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    
    var completion: ((Bool) -> Void)?
//    private var has_completed = false
        
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        log("Session Delegate ----> completed callback!")
//        guard !has_completed else {
//            log("Preventing double-completion")
//            return
//        }
//        has_completed = true
        
        guard let local_completion = self.completion else {
            log("Nil completion! - returning")
            return
        }
//        self.completion = nil
        
        if let error = error {
            log("Background POST task error: \(error)")
            local_completion(false)
            return
        }
        
        if let httpResponse = task.response as? HTTPURLResponse {
            
            switch httpResponse.statusCode {
            case 200...299:
                log("Successful POST.")
                local_completion(true)
            default:
                log("Non-success POST: \(httpResponse.statusCode)")
                local_completion(false)
            }
        } else {
            
            log("No valid HTTP response received.")
            local_completion(false)
        }
    }
        
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {

        log("URL Delegate ----> background session finished!")
    }

}

var healthStore = HKHealthStore()
var is_observer_active = false
var upload_workout_delegate: UploadWorkoutDelegate?
var url_session: URLSession?

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
        
        log("Lifecycle method load() called on HealthKit plugin.")
        
        super.load()
        
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
    func _store_start_date(start_date: Date?) {
        
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
        
        log("Updating upload properties: \(upload_target_url), \(upload_token), \(String(describing: upload_start_date))")
        // persist upload properties
        UserDefaults.standard.set(upload_target_url, forKey: "upload_target_url")
        UserDefaults.standard.set(upload_token, forKey: "upload_token")
        
        /*
         * Important to only update, never clear the start_date.
         * This function is used for initial registration (start_date is provided)
         * and for updating upload tokens (start_date is not provided).
         */
        if let start_date = upload_start_date {
            
            self._store_start_date(start_date: start_date)
            log("Stored start_date in UserDefaults: \(start_date)")
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
        
        log("initialize_background_observer called from JS context: \(start_date), \(upload_token)")
        
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
        log("initialize_background_observer initializing start_date: \(start_date)")
        self._store_start_date(start_date: start_date)

        _start_background_workout_observer() // initalizes anchor query and observer
                    
        call.resolve(["authorized": true])
    }
    
//    @MainActor
//    private func _store_background_anchor(_ anchor: HKQueryAnchor?) {
//        
//        if anchor == nil {
//            
//            UserDefaults.standard.removeObject(forKey: "backgroundAnchorKey")
//            log("Removed anchor from UserDefaults")
//            return
//        }
//        
//        do {
//            
//            let data = try NSKeyedArchiver.archivedData(withRootObject: anchor!, requiringSecureCoding: true)
//            UserDefaults.standard.set(data, forKey: "backgroundAnchorKey")
//            
//            log("-------> Stored anchor query! -> \(data.base64EncodedString())")
//        } catch {
//            log("Failed to store background anchor in UserDefaults: \(error)")
//        }
//    }

//    @MainActor
//    private func _retrieve_background_anchor() -> HKQueryAnchor? {
//        
//        guard let data = UserDefaults.standard.data(forKey: "backgroundAnchorKey") else {
//            log("XXX -> Retrieved nil for background anchor!")
//            return nil
//        }
//
//        do {
//            
//            let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
//            log("Retrieved anchor from UserDefaults -> \(data.base64EncodedString())")
//            return unarchived
//        } catch {
//            log("Failed to retrieve background anchor from UserDefults: \(error) ")
//            return nil
//        }
//    }
    
    @MainActor
    private func _retrieve_upload_endpoint_properties() -> (upload_url: String, upload_token: String) {
        
        let upload_url = UserDefaults.standard.string(forKey: "upload_target_url") ?? "https://www.swimerize.com/integrations/apple/inbound/sync/activity"
        let upload_token = UserDefaults.standard.string(forKey: "upload_token") ?? "<MISSING TOKEN>"

        return (upload_url: upload_url, upload_token: upload_token)
    }
    
    /**
     * Assumes background anchor initialized.
     */
    private func _start_background_workout_observer() {
        
        if is_observer_active {
            log("Function _start_background_workout_observer called while observer is already active.")
            return
        }
        
        log("Function _start_background_workout_observer called.")
         
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
            
            log("------> Observer query invoked!")
            
            if let error = error {
                
                log("Observer query error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            // setup background task
            var bg_task_id = UIBackgroundTaskIdentifier.invalid
            bg_task_id = UIApplication.shared.beginBackgroundTask(withName: "com.swimerize.background_sync_workout") {
                
                UIApplication.shared.endBackgroundTask(bg_task_id)
                bg_task_id = UIBackgroundTaskIdentifier.invalid
            }
            
            defer {
                if bg_task_id != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(bg_task_id)
                    bg_task_id = UIBackgroundTaskIdentifier.invalid
                }
            }
                           
//            var current_anchor: HKQueryAnchor?
            var start_date: Date?
            Task {
                
                start_date = await MainActor.run {
                    self._retrieve_start_date()
                }
                
                if start_date == nil {
                    
                    log("Error: Start date is nil! Background observer requires a start date!")
                    completionHandler()
                    return
                }
                
                log("Start date to query workouts: \(String(describing: start_date))")
                
                self._internal_fetch_workouts(
                    startDate: start_date,
                    endDate: nil,
                    anchor: nil, // used to be 'current_anchor' when we were passing an anchor around,
                    caller_id: "_start_background_workout_observer"
                ) { [weak self] workouts, latest_start_date in
                    
                    guard let self = self else {return}
                    
                    log("-----> Observer query -> Retrieved background workouts: \(workouts.count) with latest_start_date: \(String(describing: latest_start_date))")
                    
                    if workouts.count == 0 {
                        log("No workouts to upload.")
                        completionHandler()
                        return
                    }
                    
                    let start_date_to_persist = latest_start_date
                    Task {@MainActor in
                        
                        log("Within first Task boundary: \(String(describing: start_date_to_persist))")
                        let upload_properties = self._retrieve_upload_endpoint_properties()
                        log("Still right date (1): \(String(describing: start_date_to_persist))")

                        let upload_url = upload_properties.upload_url
                        let upload_token = upload_properties.upload_token
                        
                        /*
                         * Serialize JSON to a file
                         */
                        var payload_json = JSObject()
                        payload_json["workout_results"] = workouts
                        payload_json["upload_token"] = upload_token
                        
                        log("Still right date (2): \(String(describing: start_date_to_persist))")

                        let serializable_results = self._prepare_for_serialization(in: payload_json)
                        guard let json_data = try? JSONSerialization.data(withJSONObject: serializable_results) else {
                            
                            log("Error serializing workout for POST")
                            completionHandler()
                            return
                        }
                        log("Still right date (3): \(String(describing: start_date_to_persist))")

                        let tmp_dir = FileManager.default.temporaryDirectory
                        let tmp_file_url = tmp_dir.appendingPathComponent("tmp_workout_payload.json")
                        do {
                            try json_data.write(to: tmp_file_url)
                        } catch {
                            log("Unable to write tmp file: \(error)")
                            completionHandler()
                            return
                        }
                        log("Still right date (4): \(String(describing: start_date_to_persist))")

                        log("-----> Posting to \(upload_url) w/ token \(upload_token)")
                        
                        // submit workout contents
                        log("Still right date (5): \(String(describing: start_date_to_persist))")
                        let inner_start_date_to_persist = start_date_to_persist
                        log("##### -> Assigned inner^2 date: \(String(describing: inner_start_date_to_persist)) from \(String(describing: start_date_to_persist))")
                        
                        // clear-out global state before execution (can't do it within _post_workout due to deallocation race conditions
                        upload_workout_delegate = nil
                        url_session = nil

                        self._post_workout(tmp_payload_file_url: tmp_file_url, upload_url: upload_url, upload_token: upload_token) { success in
                            
                            if success {
                                
                                log("POST background call successfully submitted.")
                                
                                // successfully processed callback, so store updated start date
                                log("About to persist latest start date: \(String(describing: inner_start_date_to_persist))")
                                
                                let final_inner_start_date_to_persist = inner_start_date_to_persist
                                Task {@MainActor in
                                    log("Inside Task - about to persist latest start_date: \(String(describing: final_inner_start_date_to_persist))")
                                    self._store_start_date(start_date: final_inner_start_date_to_persist)
                                }
                                
                            } else {
                                
                                log("Failed to POST background workout data.")
                            }
                            
                            // clear file
                            do {
                                try FileManager.default.removeItem(at: tmp_file_url)
                                log("TMP payload file removed!")
                            } catch {
                                log("Unable to remove tmp file: \(error)")
                            }
                            
                            // finalize callback
                            completionHandler()
                        }
                    }
                }
            }
        }
        
        healthStore.execute(observerQuery)
        
        is_observer_active = true
        log("------> Observer query registered!")

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

//    @MainActor
    private func _post_workout(tmp_payload_file_url: URL, upload_url: String, upload_token: String, completion: @escaping (Bool) -> Void) {
        
        log("--------> Posting workout")
                        
        let config = URLSessionConfiguration.background(withIdentifier: "com.swimerize.bg_workout_sync_session")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        
        let upload_delegate = UploadWorkoutDelegate()
        upload_delegate.completion = {success in
                
            log("_post_workout continuation called with success: \(success)")
            
            /*
             * NOTE: As much as I would like to clear out the previously-stored
             *       upload_delegate and completion here, the runtime environment
             *       deallocates the completion before it has a chance to run.
             *       Therefore, it is the responsibility of the caller to clear state
             *       before execution.
             */
            
            completion(success)
        }
        upload_workout_delegate = upload_delegate
        
        url_session = URLSession(configuration: config, delegate: upload_workout_delegate!, delegateQueue: nil)
        
        guard let url = URL(string: upload_url) else {
            log("Unable to determine POST url endpoint: \(upload_url)")
            completion(false)
            return
        }
                
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        log("Calling url_session...")
        let task = url_session!.uploadTask(with: request, fromFile: tmp_payload_file_url)
        task.resume()
        
//        // prevents it from being dealocated
//        let _ = { [upload_workout_delegate] in
//            log("_post_workout delegate retained... \(upload_workout_delegate.hashValue)")
//        }
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
    
    private func _internal_fetch_workouts(
        startDate: Date?,
        endDate: Date?,
        anchor: HKQueryAnchor?,
        caller_id: String,
        completion: @escaping([JSObject], Date?) -> Void
    ) {
    
        log("----> \(caller_id) => _internal_fetch_workouts... start: \(String(describing: startDate)), end: \(String(describing: endDate))");
        
        var effective_start_date = startDate
        if startDate == nil && endDate == nil && anchor == nil {
            log("WARNING: _internal_fetch_workouts -> defaulting to effective_start_date to now...")
            effective_start_date = Date()
        }
        
        let workoutType = HKObjectType.workoutType()
                
        var predicate: NSPredicate?
        log("Initializing predicate for _internal_fetch_workouts...")
        if let start = effective_start_date, let end = endDate {
            predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        } else if let start = effective_start_date {
            predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        } else if let end = endDate {
            predicate = HKQuery.predicateForSamples(withStart: nil, end: end, options: .strictEndDate)
        }
        
        let query = HKAnchoredObjectQuery(
            type: workoutType,
            predicate: predicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, new_samples, deleted_samples, new_anchor, error in
            
            guard let self = self else {
                log("_internal_fetch_workouts 'self' is nil!... returning!")
                return
            }
            
            if let error = error {
                log("\(caller_id) Error fetching workouts: \(error.localizedDescription)")
                completion([], nil)
                return
            }
            
//            let anchors_equal = is_anchor_equal(anchor: anchor, new_anchor: new_anchor)
//            if (anchors_equal) {
//                log("New anchor is equal to old one - returning no results")
//                completion([], nil)
//            } else {
//                log("New anchor is different than old one: \(String(describing: anchor)) vs \(String(describing: new_anchor))")
//            }
            
            guard let workouts = new_samples as? [HKWorkout], !workouts.isEmpty else {
                
                log("\(caller_id) _internal_fetch_workouts: No workouts found")
                completion([], nil)
                return
            }

            Task {
                
                let results = await self.generate_sample_output(results: workouts) ?? []
                
                // obtain the latest start date
                // let latest_start_date = workouts.last?.startDate
                let latest_start_date = workouts.max {$0.endDate < $1.endDate }?.endDate
                let first_end_date = workouts.first?.endDate
                let latest_end_date = workouts.last?.endDate
                log("======> first and last sanity check: \(String(describing: first_end_date)) and \(String(describing: latest_end_date))")
                
                log("\(caller_id) _internal_fetch_workouts: \(results.count) workouts found => latest_start_date: \(String(describing: latest_start_date))")
                completion(results, latest_start_date)
            }
        }
        
        healthStore.execute(query)
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

        _internal_fetch_workouts(startDate: startDate, endDate: endDate, anchor: nil, caller_id: "fetch_workouts") { (workout_results, _) in
        
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

//// MARK: - URLSessionDelegate
//extension SwimifiedCapacitorHealthKitPlugin: URLSessionDelegate, URLSessionTaskDelegate {
//    
//    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
//        
//        
//    }
//    
//    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
//        
//    }
//}
