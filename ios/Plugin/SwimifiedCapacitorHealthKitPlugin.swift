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
    
    @objc public func request_permissions(_ call: CAPPluginCall) {
        
        if !HKHealthStore.isHealthDataAvailable() {
            return call.reject("Apple HealthKit is not available on this device.")
        }
        
        let writeTypes: Set<HKSampleType> = []
        let readTypes: Set<HKSampleType> = [
                                                HKWorkoutType.workoutType(),
                                                HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate)!,
                                                HKSeriesType.workoutRoute()
                                           ];
        
        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, _ in
            
            if !success {
                call.reject("Unable to get needed HealthKit permissions.")
                return
            }
            call.resolve()
        }
        
        return;
    }
    
    @objc func fetch_workouts(_ call: CAPPluginCall) {
        
        guard let startDate = call.getDate("start_date") else {
            return call.reject("Parameter start_date is required!")
        }
        guard let endDate = call.getDate("end_date") else {
            return call.reject("Parameter end_date is required!")
        }
        
        let limit: Int = HKObjectQueryNoLimit
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: HKQueryOptions.strictStartDate)
        
        let sampleType: HKSampleType = HKWorkoutType.workoutType()
        
        let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: limit, sortDescriptors: nil) {
            _, results, error in
            
            if let error_message = error?.localizedDescription {
                return call.reject("Unable to fetch Apple HealthKit results. Please consider re-authorizing Apple HealthKit integration. Error message: \(error_message)")
            }
            
            Task {
                guard let output: [JSObject] = await self.generate_sample_output(results: results) else {
                    return call.reject("Unable to obtain Apple HealthKit results. Support is limited to iOS version 16 and above.")
                }
                
                call.resolve([
                    "count": output.count,
                    "results": output,
                ])
             }
        }
        healthStore.execute(query)
    }
    
    func generate_sample_output(results: [HKSample]?) async -> [JSObject]? {
        
        if results == nil {
            return []
        }

        var output: [JSObject] = []

        for result in results! {

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
                    let start_date = activity.startDate
                    let end_date = activity.endDate
                    let uuid = activity.uuid
                    
                    // events
                    var events: [JSObject] = []
                    for event in activity.workoutEvents {
                        
                        events.append(generate_event_output(event: event))
                    }
                    
                    // heart rate data
                    let heart_rate_type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
                    let predicate = HKQuery.predicateForSamples(withStart: activity.startDate,
                                                                end: activity.endDate,
                                                                options: .strictStartDate)
                    
                    var heart_rate_data: [JSObject] = []
                    let query = HKSampleQuery(sampleType: heart_rate_type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in
                        
                        guard let heart_rate_samples = samples as? [HKQuantitySample] else { return }
                                                
                        for sample in heart_rate_samples {
                            
                            let bpm = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))

                            var js_obj = JSObject()
                            js_obj["start_date"] = sample.startDate
                            js_obj["end_date"] = sample.endDate
                            js_obj["motion_context"] = sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber
                            js_obj["heart_rate"] = bpm
                            
                            heart_rate_data.append(js_obj)
                        }
                    }
                    
                    healthStore.execute(query)

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
    
    func generate_event_output(event: HKWorkoutEvent) -> JSObject {
        
        let type: HKWorkoutEventType = event.type
        let start_timestamp: Date = event.dateInterval.start
        let end_timestamp: Date = event.dateInterval.end
        var stroke_style = event.metadata?[HKMetadataKeySwimmingStrokeStyle] as? NSNumber

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


