export interface SwimifiedCapacitorHealthKitPlugin {
    request_permissions(): Promise<void>;
    is_available(): Promise<void>;
    fetch_workouts(opts: {
        start_date: Date;
        end_date: Date;
    }): Promise<WorkoutResults>;
    initialize_background_observer(opts: {
        start_date: Date;
        upload_url: string;
        upload_token: string;
    }): Promise<void>;
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
export interface StrokeCountData {
    start_time: Date;
    end_time: Date;
    count: number;
}
export interface VO2MaxData {
    start_time: Date;
    end_time: Date;
    vo2max_value: number;
}
export interface HeartRateData {
    start_date: Date;
    end_date: Date;
    motion_context: number;
    heart_rate: string;
}
export interface HKWorkoutActivity {
    uuid: string;
    start_date: Date;
    end_date: Date;
    HKWorkoutEvents: HKWorkoutEvent[];
    HKLapLength?: number;
    HKSwimLocationType: number;
    HKWorkoutActivityType: number;
    heart_rate_data: HeartRateData[];
    stroke_count_data: StrokeCountData[];
    vo2max_data: VO2MaxData[];
}
export interface HKWorkoutEvent {
    type: number;
    start_timestamp: Date;
    end_timestamp: Date;
    stroke_style: number;
    swolf: string;
}
export interface CLLocation {
    timestamp: Date;
    latitude: number;
    longitude: number;
    altitude: number;
}
