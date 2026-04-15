# app/state.py
latest_data = {
    "region_counts": {},
    "class_counts": {},
    "breakdown": {
        "childMale": 0,
        "adultMale": 0,
        "seniorMale": 0,
        "childFemale": 0,
        "adultFemale": 0,
        "seniorFemale": 0,
    },
    "total_passenger_counts": 0,
    "trip_phase": "UNKNOWN",
    "dist_to_start_m": -1.0,
    "dist_to_finish_m": -1.0,
}