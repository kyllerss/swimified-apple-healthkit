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
    
    enum HKSampleError: Error {
        
        case workoutRouteRequestFailed
    }
    
    @objc func is_available(_ call: CAPPluginCall) {
        
        if HKHealthStore.isHealthDataAvailable() {
            return call.resolve()
        } else {
            return call.reject("HealthKit is not available in this device.")
        }
    }
    
    @objc public func request_permissions(_ call: CAPPluginCall) {
        
        if !HKHealthStore.isHealthDataAvailable() {
            return call.reject("Health data not available")
        }
        
        let writeTypes: Set<HKSampleType> = []
        let readTypes: Set<HKSampleType> = [
                                                HKWorkoutType.workoutType(),
                                                HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate)!,
                                                HKSeriesType.workoutRoute()
                                           ];
        
        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, _ in
            
            if !success {
                call.reject("Could not get requested permissions")
                return
            }
            call.resolve()
        }
        
        return;
    }
    
    @objc func fetch_workouts(_ call: CAPPluginCall) {
        
        guard let startDate = call.getDate("startDate") else {
            return call.reject("Parameter startDate is required!")
        }
        guard let endDate = call.getDate("endDate") else {
            return call.reject("Parameter endDate is required!")
        }
        
//        print("Fetch workout parameters: ", startDate, endDate);
        
        let limit: Int = HKObjectQueryNoLimit
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: HKQueryOptions.strictStartDate)
        
        let sampleType: HKSampleType = HKWorkoutType.workoutType()
        
        let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: limit, sortDescriptors: nil) {
            _, results, _ in
            
            Task {
                guard let output: [JSObject] = await self.generate_sample_output(results: results) else {
                    return call.reject("Unable to process results")
                }
                
    //            print("Fetch workout result: ", output)
                
                call.resolve([
                    "count": output.count,
                    "results": output,
                ])
             }
        }
        healthStore.execute(query)
    }
    
    func generate_sample_output(results: [HKSample]?) async -> [JSObject]? {
        
//        output.append([
//            "uuid": "1234-1234-1234-1234",
//            "startDate": Date(),
//            "endDate": Date(),
//            "source": "healthkit dummy source",
//            "sourceBundleId": "healthkit dummy bundle id",
//            "device": getDeviceInformation(device: nil) as Any,
//            "HKWorkoutActivityId": 1,
//        ])
//        return output
        if results == nil {
            return []
        }

        var output: [JSObject] = []

        for result in results! {

            guard let sample = result as? HKWorkout else {
                continue
            }

            // only process swim-related activities
            if sample.workoutActivityType != HKWorkoutActivityType.swimming
                && sample.workoutActivityType != HKWorkoutActivityType.swimBikeRun {
                continue
            }

            /*
             * NOTE: In case of a simple swim, there is one entry.
             *       In case of triathlon, multiple entries of which one is a swim.
             */
            for activity in sample.workoutActivities {
                
                let workout_config = activity.workoutConfiguration
                
                if workout_config.activityType != HKWorkoutActivityType.swimming {
                    continue
                }
        
                let lap_length = workout_config.lapLength
                let location_type = workout_config.swimmingLocationType
                let start_date = activity.startDate
                let end_date = activity.endDate
                let source = sample.sourceRevision.source.name
                let source_bundle_id = sample.sourceRevision.source.bundleIdentifier
                let uuid = activity.uuid
                let device = get_device_information(device: sample.device)
                let workout_activity_id = sample.workoutActivityType.rawValue

                // events
                var events: [JSObject] = []
                for event in activity.workoutEvents {
                    
                    events.append(generate_event_output(event: event))
                }

                // GPS coordinates
                do {
                    let route: HKWorkoutRoute = try await get_route(for: activity)
                    let locations = try await get_locations(for: route)
                    
                    var cl_locations: [JSObject] = []
                    for location in locations {
                        
                        cl_locations.append(generate_location_output(from: location))
                    }
                          
                    var js_obj = JSObject()
                    
                    js_obj["uuid"] = uuid.uuidString
                    js_obj["start_date"] = start_date
                    js_obj["end_date"] = end_date
                    js_obj["source"] = source
                    js_obj["source_bundle_id"] = source_bundle_id
                    js_obj["device"] = device
                    js_obj["HKWorkoutActivityId"] = Int(workout_activity_id)
                    js_obj["HKWorkoutEvents"] = events
                    js_obj["CLLocations"] = cl_locations
                    js_obj["HKLapLength"] = lap_length?.doubleValue(for: .meter())
                    js_obj["HKSwimLocationType"] = location_type.rawValue
                    
                    output.append(js_obj)
                } catch {
                    print("Unable to process CLLocations for ", sample.uuid.uuidString)
                }
            }
        }

        return output
     }

    func generate_event_output(event: HKWorkoutEvent) -> JSObject {
        
        let type: HKWorkoutEventType = event.type
        let start_timestamp: Date = event.dateInterval.start
        let end_timestamp: Date = event.dateInterval.end
        var stroke_style: HKSwimmingStrokeStyle;
        if let stroke_style_tmp = event.metadata?[HKMetadataKeySwimmingStrokeStyle] as? HKSwimmingStrokeStyle {
            stroke_style = stroke_style_tmp
        } else {
            stroke_style = .unknown
        }
        
        var to_return = JSObject()
        
        to_return["type"] = type.rawValue
        to_return["start_timestamp"] = start_timestamp
        to_return["end_timestamp"] = end_timestamp
        to_return["stroke_style"] = stroke_style.rawValue
        
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
    
    private func get_route(for workout: HKWorkoutActivity) async throws -> HKWorkoutRoute {
        try await withCheckedThrowingContinuation { continuation in
            get_route(for: workout) { result in
                continuation.resume(with: result)
            }
        }
    }
    private func get_route(for workout: HKWorkoutActivity, completion: @escaping (Result<HKWorkoutRoute, Error>) -> Void) {
        
        let predicate = HKQuery.predicateForObject(with: workout.uuid)
        let query = HKAnchoredObjectQuery(type: HKSeriesType.workoutRoute(),
                                          predicate: predicate,
                                          anchor: nil,
                                          limit: HKObjectQueryNoLimit)
        { _, samples, _, _, error in
            if let resultError = error {
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
            if let resultError = error {
                return completion(.failure(resultError))
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

