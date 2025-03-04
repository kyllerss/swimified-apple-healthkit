# swimified-apple-healthkit

Swimified-specific Capacitor plugin for accessing Apple HealthKit workout data.

## Install

```bash
npm install swimified-apple-healthkit
npx cap sync
```

## API

<docgen-index>

* [`request_permissions()`](#request_permissions)
* [`is_available()`](#is_available)
* [`fetch_workouts(...)`](#fetch_workouts)
* [`initialize_background_observer(...)`](#initialize_background_observer)
* [Interfaces](#interfaces)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### request_permissions()

```typescript
request_permissions() => Promise<void>
```

--------------------


### is_available()

```typescript
is_available() => Promise<void>
```

--------------------


### fetch_workouts(...)

```typescript
fetch_workouts(opts: { start_date: Date; end_date: Date; }) => Promise<WorkoutResults>
```

| Param      | Type                                                                                       |
| ---------- | ------------------------------------------------------------------------------------------ |
| **`opts`** | <code>{ start_date: <a href="#date">Date</a>; end_date: <a href="#date">Date</a>; }</code> |

**Returns:** <code>Promise&lt;<a href="#workoutresults">WorkoutResults</a>&gt;</code>

--------------------


### initialize_background_observer(...)

```typescript
initialize_background_observer(opts: { start_date: Date; }) => Promise<void>
```

| Param      | Type                                                   |
| ---------- | ------------------------------------------------------ |
| **`opts`** | <code>{ start_date: <a href="#date">Date</a>; }</code> |

--------------------


### Interfaces


#### WorkoutResults

| Prop          | Type                         |
| ------------- | ---------------------------- |
| **`count`**   | <code>number</code>          |
| **`results`** | <code>WorkoutResult[]</code> |


#### WorkoutResult

| Prop                      | Type                                                            |
| ------------------------- | --------------------------------------------------------------- |
| **`uuid`**                | <code>string</code>                                             |
| **`start_date`**          | <code><a href="#date">Date</a></code>                           |
| **`end_date`**            | <code><a href="#date">Date</a></code>                           |
| **`source`**              | <code>string</code>                                             |
| **`source_bundle_id`**    | <code>string</code>                                             |
| **`device`**              | <code><a href="#deviceinformation">DeviceInformation</a></code> |
| **`HKWorkoutActivityId`** | <code>number</code>                                             |
| **`HKWorkoutActivities`** | <code>HKWorkoutActivity[]</code>                                |
| **`CLLocations`**         | <code>CLLocation[]</code>                                       |


#### Date

Enables basic storage and retrieval of dates and times.

| Method                 | Signature                                                                                                    | Description                                                                                                                             |
| ---------------------- | ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| **toString**           | () =&gt; string                                                                                              | Returns a string representation of a date. The format of the string depends on the locale.                                              |
| **toDateString**       | () =&gt; string                                                                                              | Returns a date as a string value.                                                                                                       |
| **toTimeString**       | () =&gt; string                                                                                              | Returns a time as a string value.                                                                                                       |
| **toLocaleString**     | () =&gt; string                                                                                              | Returns a value as a string value appropriate to the host environment's current locale.                                                 |
| **toLocaleDateString** | () =&gt; string                                                                                              | Returns a date as a string value appropriate to the host environment's current locale.                                                  |
| **toLocaleTimeString** | () =&gt; string                                                                                              | Returns a time as a string value appropriate to the host environment's current locale.                                                  |
| **valueOf**            | () =&gt; number                                                                                              | Returns the stored time value in milliseconds since midnight, January 1, 1970 UTC.                                                      |
| **getTime**            | () =&gt; number                                                                                              | Gets the time value in milliseconds.                                                                                                    |
| **getFullYear**        | () =&gt; number                                                                                              | Gets the year, using local time.                                                                                                        |
| **getUTCFullYear**     | () =&gt; number                                                                                              | Gets the year using Universal Coordinated Time (UTC).                                                                                   |
| **getMonth**           | () =&gt; number                                                                                              | Gets the month, using local time.                                                                                                       |
| **getUTCMonth**        | () =&gt; number                                                                                              | Gets the month of a <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                                             |
| **getDate**            | () =&gt; number                                                                                              | Gets the day-of-the-month, using local time.                                                                                            |
| **getUTCDate**         | () =&gt; number                                                                                              | Gets the day-of-the-month, using Universal Coordinated Time (UTC).                                                                      |
| **getDay**             | () =&gt; number                                                                                              | Gets the day of the week, using local time.                                                                                             |
| **getUTCDay**          | () =&gt; number                                                                                              | Gets the day of the week using Universal Coordinated Time (UTC).                                                                        |
| **getHours**           | () =&gt; number                                                                                              | Gets the hours in a date, using local time.                                                                                             |
| **getUTCHours**        | () =&gt; number                                                                                              | Gets the hours value in a <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                                       |
| **getMinutes**         | () =&gt; number                                                                                              | Gets the minutes of a <a href="#date">Date</a> object, using local time.                                                                |
| **getUTCMinutes**      | () =&gt; number                                                                                              | Gets the minutes of a <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                                           |
| **getSeconds**         | () =&gt; number                                                                                              | Gets the seconds of a <a href="#date">Date</a> object, using local time.                                                                |
| **getUTCSeconds**      | () =&gt; number                                                                                              | Gets the seconds of a <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                                           |
| **getMilliseconds**    | () =&gt; number                                                                                              | Gets the milliseconds of a <a href="#date">Date</a>, using local time.                                                                  |
| **getUTCMilliseconds** | () =&gt; number                                                                                              | Gets the milliseconds of a <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                                      |
| **getTimezoneOffset**  | () =&gt; number                                                                                              | Gets the difference in minutes between the time on the local computer and Universal Coordinated Time (UTC).                             |
| **setTime**            | (time: number) =&gt; number                                                                                  | Sets the date and time value in the <a href="#date">Date</a> object.                                                                    |
| **setMilliseconds**    | (ms: number) =&gt; number                                                                                    | Sets the milliseconds value in the <a href="#date">Date</a> object using local time.                                                    |
| **setUTCMilliseconds** | (ms: number) =&gt; number                                                                                    | Sets the milliseconds value in the <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                              |
| **setSeconds**         | (sec: number, ms?: number \| undefined) =&gt; number                                                         | Sets the seconds value in the <a href="#date">Date</a> object using local time.                                                         |
| **setUTCSeconds**      | (sec: number, ms?: number \| undefined) =&gt; number                                                         | Sets the seconds value in the <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                                   |
| **setMinutes**         | (min: number, sec?: number \| undefined, ms?: number \| undefined) =&gt; number                              | Sets the minutes value in the <a href="#date">Date</a> object using local time.                                                         |
| **setUTCMinutes**      | (min: number, sec?: number \| undefined, ms?: number \| undefined) =&gt; number                              | Sets the minutes value in the <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                                   |
| **setHours**           | (hours: number, min?: number \| undefined, sec?: number \| undefined, ms?: number \| undefined) =&gt; number | Sets the hour value in the <a href="#date">Date</a> object using local time.                                                            |
| **setUTCHours**        | (hours: number, min?: number \| undefined, sec?: number \| undefined, ms?: number \| undefined) =&gt; number | Sets the hours value in the <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                                     |
| **setDate**            | (date: number) =&gt; number                                                                                  | Sets the numeric day-of-the-month value of the <a href="#date">Date</a> object using local time.                                        |
| **setUTCDate**         | (date: number) =&gt; number                                                                                  | Sets the numeric day of the month in the <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                        |
| **setMonth**           | (month: number, date?: number \| undefined) =&gt; number                                                     | Sets the month value in the <a href="#date">Date</a> object using local time.                                                           |
| **setUTCMonth**        | (month: number, date?: number \| undefined) =&gt; number                                                     | Sets the month value in the <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                                     |
| **setFullYear**        | (year: number, month?: number \| undefined, date?: number \| undefined) =&gt; number                         | Sets the year of the <a href="#date">Date</a> object using local time.                                                                  |
| **setUTCFullYear**     | (year: number, month?: number \| undefined, date?: number \| undefined) =&gt; number                         | Sets the year value in the <a href="#date">Date</a> object using Universal Coordinated Time (UTC).                                      |
| **toUTCString**        | () =&gt; string                                                                                              | Returns a date converted to a string using Universal Coordinated Time (UTC).                                                            |
| **toISOString**        | () =&gt; string                                                                                              | Returns a date as a string value in ISO format.                                                                                         |
| **toJSON**             | (key?: any) =&gt; string                                                                                     | Used by the JSON.stringify method to enable the transformation of an object's data for JavaScript Object Notation (JSON) serialization. |


#### DeviceInformation

| Prop                   | Type                |
| ---------------------- | ------------------- |
| **`name`**             | <code>string</code> |
| **`model`**            | <code>string</code> |
| **`manufacturer`**     | <code>string</code> |
| **`hardware_version`** | <code>string</code> |
| **`software_version`** | <code>string</code> |


#### HKWorkoutActivity

| Prop                        | Type                                  |
| --------------------------- | ------------------------------------- |
| **`uuid`**                  | <code>string</code>                   |
| **`start_date`**            | <code><a href="#date">Date</a></code> |
| **`end_date`**              | <code><a href="#date">Date</a></code> |
| **`HKWorkoutEvents`**       | <code>HKWorkoutEvent[]</code>         |
| **`HKLapLength`**           | <code>number</code>                   |
| **`HKSwimLocationType`**    | <code>number</code>                   |
| **`HKWorkoutActivityType`** | <code>number</code>                   |
| **`heart_rate_data`**       | <code>HeartRateData[]</code>          |
| **`stroke_count_data`**     | <code>StrokeCountData[]</code>        |
| **`vo2max_data`**           | <code>VO2MaxData[]</code>             |


#### HKWorkoutEvent

| Prop                  | Type                                  |
| --------------------- | ------------------------------------- |
| **`type`**            | <code>number</code>                   |
| **`start_timestamp`** | <code><a href="#date">Date</a></code> |
| **`end_timestamp`**   | <code><a href="#date">Date</a></code> |
| **`stroke_style`**    | <code>number</code>                   |
| **`swolf`**           | <code>string</code>                   |


#### HeartRateData

| Prop                 | Type                                  |
| -------------------- | ------------------------------------- |
| **`start_date`**     | <code><a href="#date">Date</a></code> |
| **`end_date`**       | <code><a href="#date">Date</a></code> |
| **`motion_context`** | <code>number</code>                   |
| **`heart_rate`**     | <code>string</code>                   |


#### StrokeCountData

| Prop             | Type                                  |
| ---------------- | ------------------------------------- |
| **`start_time`** | <code><a href="#date">Date</a></code> |
| **`end_time`**   | <code><a href="#date">Date</a></code> |
| **`count`**      | <code>number</code>                   |


#### VO2MaxData

| Prop               | Type                                  |
| ------------------ | ------------------------------------- |
| **`start_time`**   | <code><a href="#date">Date</a></code> |
| **`end_time`**     | <code><a href="#date">Date</a></code> |
| **`vo2max_value`** | <code>number</code>                   |


#### CLLocation

| Prop            | Type                                  |
| --------------- | ------------------------------------- |
| **`timestamp`** | <code><a href="#date">Date</a></code> |
| **`latitude`**  | <code>number</code>                   |
| **`longitude`** | <code>number</code>                   |
| **`altitude`**  | <code>number</code>                   |

</docgen-api>
