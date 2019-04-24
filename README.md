# Cordova Walking Distance Estimation Plugin

A Cordova plugin which allows the walking distance estimation of persons. The plugin utilizes a step counting and step length calibration approach. Supported platforms are Android and iOS with an analogous implementation targeting inter-platform comparability of results.

## Supported Platforms

- iOS
- Android

## Usage

To use this plugin, add `stepdist` to your Cordova application using the Cordova command line interface (CLI):

```yaml
cordova plugin add cordova-plugin-todo
```

Listening to walking distance events (which automatically starts the estimation):

```yaml
var onWalkingDistanceEvent = function(walkingDistanceEvent) {
    // walkingDistanceEvent.distance}
    // walkingDistanceEvent.elevation}
    // walkingDistanceEvent.steps}
};
document.addEventListener("walkingdistance", onWalkingDistanceEvent);
```

Stop listening to walking distance events (to stop the estimation):

```yaml
document.removeEventListener("walkingdistance", onWalkingDistanceEvent);
```

Listening to plugin status event (optionally, for monitoring purposes):

```yaml
var onStepDistStatusEvent = function(stepDistStatusEvent) {
    // stepDistStatusEvent.isReadyToStart}
    // stepDistStatusEvent.stepLength}
    // stepDistStatusEvent.lastCalibrated}
    // stepDistStatusEvent.bodyHeight}
};
document.addEventListener("stepdiststatus", onStepDistStatusEvent);
```

Configuration methods (optional):

```yaml
stepdist.setBodyHeight(1.89); // Specified in meters
stepdist.disableGNSSCalibration();
stepdist.resetData();
```