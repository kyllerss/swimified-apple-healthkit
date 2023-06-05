export interface SwimifiedCapacitorHealthKitPlugin {
    request_permissions(): Promise<void>;
    is_available(): Promise<void>;
    fetch_workouts(opts: {
        start_date: Date;
        end_date: Date;
    }): Promise<WorkoutResults>;
}
export interface WorkoutResults {
    count: number;
    results: WorkoutResult[];
}
export interface WorkoutResult {
    uuid: string;
    start_date: Date;
    end_date: Date;
    source: string;
    source_bundle_id: string;
    device?: DeviceInformation;
    HKWorkoutActivityId: number;
    HKWorkoutActivities: HKWorkoutActivity[];
    CLLocations: CLLocation[];
}
export interface DeviceInformation {
    name: string;
    model: string;
    manufacturer: string;
    hardware_version: string;
    software_version: string;
}
export interface HKWorkoutActivity {
    uuid: string;
    start_date: Date;
    end_date: Date;
    HKWorkoutEvents: HKWorkoutEvent[];
    HKLapLength?: number;
    HKSwimLocationType: number;
    HKWorkoutActivityType: number;
}
export interface HKWorkoutEvent {
    type: number;
    start_timestamp: Date;
    end_timestamp: Date;
    stroke_style: number;
}
export interface CLLocation {
    timestamp: Date;
    latitude: number;
    longitude: number;
    altitude: number;
}
