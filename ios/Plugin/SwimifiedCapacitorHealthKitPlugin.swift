import Foundation
import Capacitor
import HealthKit

var healthStore = HKHealthStore()

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(SwimifiedCapacitorHealthKitPlugin)
public class SwimifiedCapacitorHealthKitPlugin: CAPPlugin {
    
    @objc public func request_permissions(_ call: CAPPluginCall) {
        
        if !HKHealthStore.isHealthDataAvailable() {
            return call.reject("Health data not available")
        }
        
        print("Call to authorize HealthKit...");
        
        let writeTypes: Set<HKSampleType> = []
        let readTypes: Set<HKSampleType> = [HKWorkoutType.workoutType()];
        
        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, _ in
            
            print("Finished authorization call: ", success)
            
            call.resolve()
//            if !success {
//                call.reject("Could not get permission")
//                return
//            }
//            call.resolve()
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
        
        print("Fetch workout parameters: ", startDate, endDate);
        
        let limit: Int = HKObjectQueryNoLimit
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: HKQueryOptions.strictStartDate)
        
        let sampleType: HKSampleType = HKWorkoutType.workoutType()
        
        let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: limit, sortDescriptors: nil) {
            _, results, _ in
            guard let output: [[String: Any]] = self.generateOutput(results: results) else {
                return call.reject("Unable to process results")
            }
            
            print("Fetch workout result: ", output)
            
            call.resolve([
                "count": output.count,
                "results": output,
            ])
        }
        healthStore.execute(query)
    }
    
    func generateOutput(results: [HKSample]?) -> [[String: Any]]? {
        
        var output: [[String: Any]] = []
        
        output.append([
            "uuid": "1234-1234-1234-1234",
            "startDate": Date(),
            "endDate": Date(),
            "source": "healthkit dummy source",
            "sourceBundleId": "healthkit dummy bundle id",
            "device": getDeviceInformation(device: nil) as Any,
            "HKWorkoutActivityId": 1,
        ])

        return output
//        if results == nil {
//            return output
//        }
//
//        for result in results! {
//
//            guard let sample = result as? HKWorkout else {
//                return nil
//            }
//
//             output.append([
//                 "uuid": sample.uuid.uuidString,
//                 "startDate": sample.startDate,
//                 "endDate": sample.endDate,
//                 "source": sample.sourceRevision.source.name,
//                 "sourceBundleId": sample.sourceRevision.source.bundleIdentifier,
//                 "device": getDeviceInformation(device: sample.device) as Any,
//                 "HKWorkoutActivityId": sample.workoutActivityType.rawValue,
//             ])
//         }
//         return output
     }

    func getDeviceInformation(device: HKDevice?) -> [String: String?]? {
        
        if (device == nil) {
            return nil;
        }
        
        let deviceInformation: [String: String?] = [
            "name": "dummy name",
            "model": "dummy model",
            "manufacturer": "dummy manufacturer",
            "hardwareVersion": "dummy hardware version",
            "softwareVersion": "dummy software version",
        ];
                
//        let deviceInformation: [String: String?] = [
//            "name": device?.name,
//            "model": device?.model,
//            "manufacturer": device?.manufacturer,
//            "hardwareVersion": device?.hardwareVersion,
//            "softwareVersion": device?.softwareVersion,
//        ];
        return deviceInformation;
    }
}
