import Foundation
import Capacitor
import HealthKit
import CoreLocation

var healthStore = HKHealthStore()

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(SwimifiedCapacitorHealthKitPlugin)
public class SwimifiedCapacitorHealthKitPlugin: CAPPlugin {
    
    private var backgroundAnchor: HKQueryAnchor?;
    private var backgroundStartDate: Date?;
    
    enum HKSampleError: Error {
        
        case workoutRouteRequestFailed
    }
    
    public override func load() {
        
        super.load()
        
        self.backgroundAnchor = self.retrieve_background_anchor()
        
        let authorized = self.is_authorized()
        if (authorized) {
            self.start_background_workout_observer()
        } else {
            print("HealthKit not authorized - skipping starting observer query.")
        }
    }
    
    @objc func initialize_background_observer(_ call: CAPPluginCall) {
        
        guard let startDate = call.getDate("start_date") else {

            return call.reject("Parameter start_date is required.")
        }
        
        backgroundStartDate = startDate
        
        let shouldResetAnchor = call.getBool( "reset_anchor") ?? false
        if shouldResetAnchor {
            
            backgroundAnchor = nil
            store_background_anchor(nil) // clear out stored anchor (if any)
        }
        
        call.resolve()
    }

    private func store_background_anchor(_ anchor: HKQueryAnchor?) {
        
        if anchor == nil {
            
            UserDefaults.standard.removeObject(forKey: "backgroundAnchorKey")
            return
        }
        
        do {
            
            let data = try NSKeyedArchiver.archivedData(withRootObject: anchor!, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: "backgroundAnchorKey")
        } catch {
            print("Failed to store background anchor in UserDefaults: \(error)")
        }
    }
    
    private func retrieve_background_anchor() -> HKQueryAnchor? {
        
        guard let data = UserDefaults.standard.data(forKey: "backgroundAnchorKey") else {
            return nil
        }

        do {
            
            let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
            return unarchived
        } catch {
            print("Failed to retrieve background anchor from UserDefults: \(error) ")
            return nil
        }
    }
    
    private func start_background_workout_observer() {
        
        let workoutType = HKObjectType.workoutType()
        
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) {success, error in
        
            if let error = error {
                print("Failed to enable background delivery: \(error.localizedDescription)")
            } else {
                print( "Background delivery enabled: \(success)")
            }
        }
        
        let observerQuery = HKObserverQuery(sampleType: workoutType, predicate: nil) {
            
            [weak self] _, completionHandler, error in
            guard let self = self else {return}
            
            if let error = error {
                
                print("Observer query error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            self.internal_fetch_workouts(
                startDate: self.backgroundStartDate,
                endDate: nil,
                anchor: self.backgroundAnchor
            ) { [weak self] workouts, newAnchor in
                
                guard let self = self else {return}
                
                self.backgroundAnchor = newAnchor
                self.store_background_anchor(newAnchor)
                
                // TODO PROCESS CALL AND STORE IN SERVER
                print("-----> Retrieved background workouts: \(workouts.count)")
            }
            
            // finalize callback
            completionHandler()
        }
        
        healthStore.execute(observerQuery)
    }
    
    private func reorder_dates(start: Date, end: Date) -> (start: Date, end: Date) {
        
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
    
    private func is_authorized() -> Bool {
        
        let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        return status == .sharingAuthorized
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
            
            self.start_background_workout_observer() // start listening for changes
            
            call.resolve()
        }
        
        return;
    }
    
    private func internal_fetch_workouts(
        startDate: Date?,
        endDate: Date?,
        anchor: HKQueryAnchor?,
        completion: @escaping([JSObject], HKQueryAnchor?) -> Void
    ) {
    
        let workoutType = HKObjectType.workoutType()
        
        var predicate: NSPredicate?
        if let start = startDate, let end = endDate {
            predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        } else if let start = startDate {
            predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        } else if let end = endDate {
            predicate = HKQuery.predicateForSamples(withStart: nil, end: end, options: .strictEndDate)
        }
        
        let query = HKAnchoredObjectQuery(
            type: workoutType,
            predicate: predicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, newSamples, deletedSamples, newAnchor, error in
            
            guard let self = self else { return }
            
            if let error = error {
                print("Error fetching workouts: \(error.localizedDescription)")
                completion([], anchor)
                return
            }
            
            guard let workouts = newSamples as? [HKWorkout], !workouts.isEmpty else {
                
                completion([], newAnchor)
                return
            }

            Task {
                
                let results = await self.generate_sample_output(results: workouts) ?? []
                completion(results, newAnchor)
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
        
        let reordered_dates = reorder_dates(start: startDate, end: endDate)
        startDate = reordered_dates.start
        endDate = reordered_dates.end

        internal_fetch_workouts(startDate: startDate, endDate: endDate, anchor: nil) { (workout_results, _) in
        
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
            workout_obj["device"] = get_device_information(device: sample.device)
            workout_obj["HKWorkoutActivityTypeId"] = Int(sample.workoutActivityType.rawValue)

            // process stroke count data
            let stroke_count_data: [JSObject]
            do {
                stroke_count_data = try await get_stroke_count_data(sample)
            } catch {
                stroke_count_data = []
            }

            let vo2max_data: [JSObject]
            do {
                vo2max_data = try await get_vo2max_data(sample)
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
                                        
                    let reordered_dates = reorder_dates(start: start_date, end: end_date)
                    start_date = reordered_dates.start
                    end_date = reordered_dates.end

                    // events
                    var events: [JSObject] = []
                    for event in activity.workoutEvents {
                        
                        events.append(generate_event_output(event: event))
                    }
                    
                    // heart rate data
                    let heart_rate_data: [JSObject]
                    do {
                        heart_rate_data = try await get_heart_rate(start_date: start_date, end_date: end_date, workout: sample)
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
                let route: HKWorkoutRoute = try await get_route(for: sample)
                let locations = try await get_locations(for: route)
                
                var cl_locations: [JSObject] = []
                for location in locations {
                    
                    cl_locations.append(generate_location_output(from: location))
                }
                
                workout_obj["CLLocations"] = cl_locations

            } catch {
                print("Unable to process CLLocations for ", sample.uuid.uuidString, error)
            }

            output.append(workout_obj)
        }
        
        return output
     }
    
    private func get_stroke_count_data(_ workout: HKWorkout) async throws -> [JSObject] {
        try await withCheckedThrowingContinuation { continuation in
            get_stroke_count(for: workout) { result in
                continuation.resume(with: result)
            }
        }
    } 
    private func get_stroke_count(for workout: HKWorkout, completion: @escaping (Result<[JSObject], Error>) -> Void) {
        
        var to_return: [JSObject] = []
        var start_date = workout.startDate;
        var end_date = workout.endDate;
        
        let reordered_dates = reorder_dates(start: start_date, end: end_date)
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

    private func get_vo2max_data(_ workout: HKWorkout) async throws -> [JSObject] {
        try await withCheckedThrowingContinuation { continuation in
            get_vo2max(for: workout) { result in
                continuation.resume(with: result)
            }
        }
    }
    private func get_vo2max(for workout: HKWorkout, completion: @escaping (Result<[JSObject], Error>) -> Void) {
        
        var to_return: [JSObject] = []
        var start_date = workout.startDate;
        var end_date = workout.endDate;

        let reordered_dates = reorder_dates(start: start_date, end: end_date)
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
    private func get_heart_rate(start_date: Date, end_date: Date, workout: HKWorkout) async throws -> [JSObject] {
        try await withCheckedThrowingContinuation { continuation in
            get_heart_rate(start_date: start_date, end_date: end_date, workout: workout) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    @available(iOS 15.0, *)
    private func get_heart_rate(start_date: Date, end_date: Date, workout: HKWorkout, completion: @escaping (Result<[JSObject], Error>) -> Void) {
        
        let reordered_dates = reorder_dates(start: start_date, end: end_date)
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
                            
                            series_data = try await self.get_heart_rate_series_data(start_date: start_date, end_date: end_date, series_sample: sample)
                            
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
    private func get_heart_rate_series_data(start_date: Date, end_date: Date, series_sample: HKDiscreteQuantitySample) async throws -> [JSObject] {
        try await withCheckedThrowingContinuation { continuation in
            get_heart_rate_series_data(start_date: start_date, end_date: end_date, series_sample: series_sample) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    @available(iOS 15.0, *)
    private func get_heart_rate_series_data(start_date: Date, end_date: Date, series_sample: HKDiscreteQuantitySample, completion: @escaping (Result<[JSObject], Error>) -> Void) {
        
        let reordered_dates = reorder_dates(start: start_date, end: end_date)
        var start_date = reordered_dates.start
        var end_date = reordered_dates.end

        guard let heart_rate_type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
        
            return completion(.success([])) // hr not supported
        }
        
        let in_series_sample = HKQuery.predicateForObject(with: series_sample.uuid)
        var elements: [JSObject] = []
        let detail_query = HKQuantitySeriesSampleQuery(quantityType: heart_rate_type, predicate: in_series_sample)
        {query, quantity, dateInterval, HKSample, done, error in
                        
            if let resultError = error {
                print("Error when fetching hr series data: ", resultError)
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
    
    func generate_event_output(event: HKWorkoutEvent) -> JSObject {
        
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
    
    func get_device_information(device: HKDevice?) -> JSObject? {
        
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
    
    private func get_route(for workout: HKWorkout) async throws -> HKWorkoutRoute {
        try await withCheckedThrowingContinuation { continuation in
            get_route(for: workout) { result in
                continuation.resume(with: result)
            }
        }
    }
    private func get_route(for workout: HKWorkout, completion: @escaping (Result<HKWorkoutRoute, Error>) -> Void) {
        
        let predicate = HKQuery.predicateForObjects(from: workout)
        let query = HKAnchoredObjectQuery(type: HKSeriesType.workoutRoute(),
                                          predicate: predicate,
                                          anchor: nil,
                                          limit: HKObjectQueryNoLimit)
        { _, samples, _, _, error in
            if let resultError = error {
                print("Error when fetching route: ", resultError)
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

    private func get_locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation{ continuation in
            get_locations(for: route) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    private func get_locations(for route: HKWorkoutRoute, completion: @escaping(Result<[CLLocation], Error>) -> Void) {
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

    private func generate_location_output(from location: CLLocation) -> JSObject {

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


