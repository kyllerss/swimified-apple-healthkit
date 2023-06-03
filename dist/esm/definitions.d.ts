export interface SwimifiedCapacitorHealthKitPlugin {
    request_permissions(): Promise<void>;
    fetch_workouts(startDate: Date, endDate: Date): Promise<WorkoutResults>;
    is_available(): Promise<void>;
}
export interface WorkoutResults {
    count: number;
    results: WorkoutResult[];
}
export interface WorkoutResult {
    uuid: string;
    startDate: Date;
    endDate: Date;
    source: string;
    sourceBundleId: string;
    device?: DeviceInformation;
    HKWorkoutActivityId: number;
}
export interface DeviceInformation {
    name: string;
    manufacturer: string;
    model: string;
    hardwareVersion: string;
    softwareVersion: string;
}
