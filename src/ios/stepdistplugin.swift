import CoreLocation
import CoreMotion

@objc(stepdistplugin) class stepdistplugin : CDVPlugin, CLLocationManagerDelegate {
    
    var locationManager: CLLocationManager!
    var pedometer: CMPedometer!
    
    var locationEvents: [CLLocation]!
    
    var pluginInfoEventCallbackId: String!
    var distanceEventCallbackId: String!
    var distanceFilter: Double!
    var accuracyFilter: Double!
    var perpendicularDistanceFilter: Double!
    var locationsSequenceDistanceFilter: Double!
    var stepLength: Double!
    var locationsSequenceFilter: Int!
    var distanceTraveledPersistent: Int!
    var distanceTraveledProvisional: Int!
    var stepsTakenPersistent: Int!
    var stepsTakenProvisional: Int!
    var calibrationInProgress: Bool!
    var lastCalibration: Date!
    
    @objc(startLocalization:) func startLocalization(command: CDVInvokedUrlCommand) {
        pluginInfoEventCallbackId = command.callbackId
        
        guard let arguments = command.arguments.first as? [String: Any] else {
            return
        }
        
        if let distanceFilter = arguments["distanceFilter"] as? Double,
        let accuracyFilter = arguments["accuracyFilter"] as? Double,
        let perpendicularDistanceFilter = arguments["perpendicularDistanceFilter"] as? Double,
        let locationsSequenceFilter = arguments["locationsSequenceFilter"] as? Int,
        let locationsSequenceDistanceFilter = arguments["locationsSequenceDistanceFilter"] as? Double {
            self.distanceFilter = distanceFilter
            self.accuracyFilter = accuracyFilter
            self.perpendicularDistanceFilter = perpendicularDistanceFilter
            self.locationsSequenceFilter = locationsSequenceFilter
            self.locationsSequenceDistanceFilter = locationsSequenceDistanceFilter
        } else {
            return
        }
    
        if locationManager == nil {
            locationManager = CLLocationManager()
        }
        
        if pedometer == nil {
            pedometer = CMPedometer()
        }
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = distanceFilter
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        loadStepLength()
        
        sendPluginInfo()
    }

    @objc(stopLocalization:) func stopLocalization(command: CDVInvokedUrlCommand) {
        locationManager.stopUpdatingLocation();
        locationManager = nil
        
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK
        )
        
        self.commandDelegate!.send(
            pluginResult,
            callbackId: command.callbackId
        )
    }
    
    @objc(startMeasuringDistance:) func startMeasuringDistance(command: CDVInvokedUrlCommand) {     
        distanceEventCallbackId = command.callbackId
        
        locationEvents = []
        loadStepLength()
        distanceTraveledPersistent = 0
        distanceTraveledProvisional = 0
        stepsTakenPersistent = 0
        stepsTakenProvisional = 0
        calibrationInProgress = false
        
        pedometer.startUpdates(from: Date(), withHandler: { (data, error) in
            if let pedometerData: CMPedometerData = data {
                self.processStepEvent(pedometerData)
            }
        })
    }

    @objc(stopMeasuringDistance:) func stopMeasuringDistance(command: CDVInvokedUrlCommand) {     
        distanceEventCallbackId = nil
        
        pedometer.stopUpdates()
        
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: "Distance measuring stopped"
        )
        
        self.commandDelegate!.send(
            pluginResult,
            callbackId: command.callbackId
        )
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let locationEvent = locations.last else {
            return
        }
        
        if pluginInfoEventCallbackId != nil {
            sendPluginInfo(accuracy: locationEvent.horizontalAccuracy)
        }
        
        if distanceEventCallbackId != nil {
            processLocationEvent(locationEvent)
        }
    }
    
    func sendPluginInfo(accuracy: Double = 9999.0) {
        var isReadyToStart = false;

        if roundAccuracy(accuracy) <= accuracyFilter {
            isReadyToStart = true;
        }
        
        var lastCalibrationString = "Not calibrated"
        if lastCalibration != nil {
            lastCalibrationString = lastCalibration.description
        }
        
        let pluginInfo: [String : Any] = ["isReadyToStart": isReadyToStart, "isCalibrating": calibrationInProgress, "lastCalibrated": lastCalibrationString, "stepLength": stepLength]
        
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: pluginInfo
        )
        pluginResult?.setKeepCallbackAs(true)
        
        self.commandDelegate!.send(
            pluginResult,
            callbackId: pluginInfoEventCallbackId
        )
    }
    
    func processStepEvent(_ stepEvent: CMPedometerData) {
        self.stepsTakenProvisional = stepEvent.numberOfSteps.intValue - stepsTakenPersistent
        self.distanceTraveledProvisional = Int(Double(stepsTakenProvisional)*stepLength)
        
        let stepsTaken: Int = stepsTakenProvisional + stepsTakenPersistent
        let distanceTraveled: Int = distanceTraveledProvisional + distanceTraveledPersistent
        
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: ["distanceTraveled": distanceTraveled, "stepsTaken": stepsTaken]
        )
        pluginResult?.setKeepCallbackAs(true)
        
        self.commandDelegate!.send(
            pluginResult,
            callbackId: distanceEventCallbackId
        )
    }
    
    func processLocationEvent(_ locationEvent: CLLocation) {
        if roundAccuracy(locationEvent.horizontalAccuracy) <= accuracyFilter {
            if locationLiesOnPath(locationEvent) {
                let cumulativeDistance = calculateCumulativeDistance()
                if cumulativeDistance >= locationsSequenceDistanceFilter {
                    calibrationInProgress = true
                    saveStepLength(cumulativeDistance / Double(stepsTakenProvisional))
                    sendPluginInfo(accuracy: locationEvent.horizontalAccuracy)
                }
            } else {
                if calibrationInProgress {
                    stepsTakenPersistent = stepsTakenProvisional
                    distanceTraveledPersistent = distanceTraveledProvisional
                }
                locationEvents.removeAll()
                calibrationInProgress = false
            }
            
            locationEvents.append(locationEvent)
        }
    }
    
    func locationLiesOnPath(_ location: CLLocation) -> Bool {
        guard locationEvents.count >= 2 else {
            return true
        }
        
        var locations: [CLLocation] = locationEvents
        if locationEvents.count >= locationsSequenceFilter {
            locations = Array(locationEvents[locationEvents.count-locationsSequenceFilter...locationsSequenceFilter])
        }
        
        let latitudes: [Double] = locations.map { $0.coordinate.latitude }
        let longitudes: [Double] = locations.map { $0.coordinate.longitude }
        
        let latitudesMean: Double = latitudes.reduce(0, +) / Double(latitudes.count)
        let longitudesMean: Double = longitudes.reduce(0, +) / Double(longitudes.count)
        
        var covariance: Double = 0.0
        for i in 0...latitudes.count-1  {
            covariance += (longitudes[i]-longitudesMean)*(latitudes[i]-latitudesMean)
        }

        let variance: Double = longitudes.reduce(0) {$0 + pow($1-longitudesMean, 2.0)}
        
        let b1: Double = covariance/variance
        let b0: Double = latitudesMean-b1*longitudesMean
        
        let r: Double = (location.coordinate.longitude+location.coordinate.latitude*b1-b0*b1)/(pow(b1, 2.0)+1)
        let longitude_perpendicular: Double = r
        let latitude_perpendicular: Double = b0+b1*r
        let dist:Double = sqrt(pow(location.coordinate.longitude-longitude_perpendicular, 2.0)+pow(location.coordinate.latitude-latitude_perpendicular, 2.0))
        
        return dist <= perpendicularDistanceFilter
    }
    
    func calculateCumulativeDistance() -> Double {
        var lastLocation: CLLocation!
        var cumulativeDistance: Double = 0.0
        
        for location: CLLocation in locationEvents {
            if lastLocation != nil {
                cumulativeDistance += location.distance(from: lastLocation)
            }
            lastLocation = location
        }
        
        return cumulativeDistance
    }

    func roundAccuracy(_ accuracy: Double) -> Double {
        return Double(round(10*accuracy)/10)
    }
    
    func loadStepLength() {
        stepLength = 0.78
        lastCalibration = nil
    }
    
    func saveStepLength(_ stepLength: Double) {
        self.stepLength = stepLength
        lastCalibration = Date()
    }

}
