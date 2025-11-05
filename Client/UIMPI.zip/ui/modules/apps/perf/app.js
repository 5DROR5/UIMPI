angular.module("beamng.apps").directive("perf", ['$timeout', function ($timeout) {
    return {
        templateUrl: '/ui/modules/apps/perf/app.html',
        replace: true,
        link: function (scope, element, attrs) {
            element.css({ transition: 'opacity 0.3s ease' })

            scope.hp = 0;
            scope.torqueNm = 0;
            scope.weight = 0;
            scope.perfPower = 0;
            scope.perfTorque = 0;
            scope.brakeTorque = 0;
            scope.avgFriction = 1.0;
            scope.drivetrain = "RWD";
            scope.propulsedWheels = 2;
            scope.totalWheels = 4;
            scope.rating = 0;
            scope.class = "D";
            scope.ratingRounded = 0;
            scope.serverMaxRating = 999;
            scope.isVehicleAllowed = true;
            scope.maxRPM = 0;
            scope.gearboxType = "N/A";
            scope.gearCount = 0;
            scope.inductionType = "NA";

            scope.statsVisible = true;

            scope.toggleStats = function () {
                scope.statsVisible = !scope.statsVisible;
            };

            let updatePending = false;

            function scheduleUpdate() {
                if (updatePending) return;
                updatePending = true;

                requestAnimationFrame(function () {
                    updatePending = false;
                    updateVisualClass();
                    scope.$apply();
                });
            }

            scope.updateData = function (dataJson) {
                try {
                    let data = {};

                    if (typeof dataJson === 'string') {
                        data = JSON.parse(dataJson);
                    } else {
                        data = dataJson;
                    }

                    scope.hp = data.hp || 0;
                    scope.torqueNm = data.torqueNm || 0;
                    scope.weight = data.weight || 0;
                    scope.perfPower = data.perfPower || 0;
                    scope.perfTorque = data.perfTorque || 0;
                    scope.brakeTorque = data.brakeTorque || 0;
                    scope.avgFriction = data.avgFriction || 1.0;
                    scope.drivetrain = data.drivetrain || "RWD";
                    scope.propulsedWheels = data.propulsedWheels || 2;
                    scope.totalWheels = 4;
                    scope.rating = data.rating || 0;
                    scope.class = data.class || "D";
                    scope.ratingRounded = data.ratingRounded || 0;
                    scope.serverMaxRating = data.serverMaxRating || 999;
                    scope.isVehicleAllowed = data.isVehicleAllowed !== false;
                    scope.maxRPM = data.maxRPM || 0;
                    scope.gearboxType = data.gearboxType || "N/A";
                    scope.gearCount = data.gearCount || 0;
                    scope.inductionType = data.inductionType || "NA";

                    scheduleUpdate();

                } catch (e) {
                    console.error('[UI-MPI] Error parsing data:', e);
                }
            };

            function updateVisualClass() {
                let displayedRating = parseInt(scope.rating);
                let ratingClass = 'ratingD';

                if (displayedRating < 100) {
                    ratingClass = 'ratingD';
                } else if (displayedRating < 200) {
                    ratingClass = 'ratingC';
                } else if (displayedRating < 300) {
                    ratingClass = 'ratingB';
                } else {
                    ratingClass = 'ratingA';
                }

                if (!scope.isVehicleAllowed) {
                    ratingClass += ' vehicle-denied';
                }

                let el = document.getElementById('ratingdisplay1_1');
                if (el) {
                    el.className = 'rating-container ' + ratingClass;
                }
            }

            scope.$on('PerformanceLimiterUpdateData', function (event, data) {
                scope.updateData(data);
            });

            $timeout(function () {
                try {
                    bngApi.engineLua(`
                        if extensions.performanceLimiter then
                            local data = extensions.performanceLimiter.getVehicleData()
                            if data then
                                local json = jsonEncode(data)
                                guihooks.trigger('PerformanceLimiterUpdateData', json)
                            end
                            extensions.performanceLimiter.requestServerLimit()
                        end
                    `);
                } catch (e) {
                    console.error('[UI-MPI] Error requesting data:', e);
                }
            }, 500);

            let vehicleChangeHandler = function () {
                $timeout(function () {
                    try {
                        bngApi.engineLua(`
                            if extensions.performanceLimiter then
                                local data = extensions.performanceLimiter.getVehicleData()
                                if data then
                                    local json = jsonEncode(data)
                                    guihooks.trigger('PerformanceLimiterUpdateData', json)
                                end
                            end
                        `);
                    } catch (e) {
                        console.error('[UI-MPI] Error in vehicle change:', e);
                    }
                }, 300);
            };

            scope.$on('VehicleFocusChanged', vehicleChangeHandler);
            scope.$on('VehicleConfigChanged', vehicleChangeHandler);
            scope.$on('$destroy', function () {
                updatePending = false;
            });
        }
    };
}]);
