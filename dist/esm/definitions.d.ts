export interface SwimifiedCapacitorHealthKitPlugin {
    request_permissions(): Promise<void>;
    is_available(): Promise<void>;
    fetch_workouts(opts: {
        startDate: Date;
        endDate: Date;
    }): Promise<WorkoutResults>;
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
