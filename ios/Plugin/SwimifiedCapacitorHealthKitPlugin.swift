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
                guard let output: [[String: Any]] = await self.generate_sample_output(results: results) else {
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
    
    func generate_sample_output(results: [HKSample]?) async -> [[String: Any]]? {
        
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

        var output: [[String: Any]] = []

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
                var events: [[String: Any?]] = []
                for event in activity.workoutEvents {
                    
                    events.append(generate_event_output(event: event))
                }

                // GPS coordinates
                var cl_locations: [[String: Any?]] = []

                do {
                    let route: HKWorkoutRoute = try await get_route(for: activity)
                    let locations = try await get_locations(for: route)
                    
                    for location in locations {
                        
                        cl_locations.append(generate_location_output(from: location))
                    }
                                            
                    output.append([
                         "uuid": sample.uuid.uuidString,
                         "startDate": start_date,
                         "endDate": end_date as Any,
                         "source": source,
                         "sourceBundleId": source_bundle_id,
                         "device": device as Any,
                         "HKWorkoutActivityId": workout_activity_id,
                         "HKWorkoutEvents": events,
                         "CLLocations": cl_locations
                     ])

                } catch {
                    print("Unable to process CLLocations for ", sample.uuid.uuidString)
                }
            }
        }

        return output
     }

    func generate_event_output(event: HKWorkoutEvent) -> [String: Any?] {
        
        let type: HKWorkoutEventType = event.type
        let start_timestamp: Date = event.dateInterval.start
        let end_timestamp: Date = event.dateInterval.end
        var stroke_style: HKSwimmingStrokeStyle;
        if let stroke_style_tmp = event.metadata?[HKMetadataKeySwimmingStrokeStyle] as? HKSwimmingStrokeStyle {
            stroke_style = stroke_style_tmp
        } else {
            stroke_style = .unknown
        }
        
        return [
            "type": type.rawValue,
            "start_timestamp": start_timestamp,
            "end_timestamp": end_timestamp,
            "stroke_style": stroke_style.rawValue
        ]
    }
    
    func get_device_information(device: HKDevice?) -> [String: String?]? {
        
        if (device == nil) {
            return nil;
        }
                        
        let deviceInformation: [String: String?] = [
            "name": device?.name,
            "model": device?.model,
            "manufacturer": device?.manufacturer,
            "hardwareVersion": device?.hardwareVersion,
            "softwareVersion": device?.softwareVersion,
        ];
        return deviceInformation;
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

    private func generate_location_output(from location: CLLocation) -> [String: Any] {

        let timestamp: Date = location.timestamp
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let altitude = location.altitude
        
        return [
            "timestamp": timestamp,
            "latitude": latitude,
            "longitude": longitude,
            "altitude": altitude
        ]
    }

}
