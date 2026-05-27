// =============================================================================
// Performance Limiter - AngularJS UI Controller
// License: The Unlicense (https://unlicense.org)
// This is free and unencumbered software released into the public domain.
// =============================================================================

angular.module("beamng.apps").directive("perf", ['$timeout', '$interval', function ($timeout, $interval) {
    return {
        templateUrl: '/ui/modules/apps/perf/app.html',
        replace: true,
        link: function (scope) {

            // =================================================================
            // STATE
            // =================================================================
            scope.hp              = 0;
            scope.torqueNm        = 0;
            scope.weight          = 0;
            scope.perfPower       = 0;
            scope.perfTorque      = 0;
            scope.brakeTorque     = 0;
            scope.avgFriction     = 1.0;
            scope.drivetrain      = "RWD";
            scope.propulsedWheels = 2;
            scope.totalWheels     = 4;
            scope.rating          = 0;
            scope.class           = "D";
            scope.ratingRounded   = 0;
            scope.serverMaxRating     = 999;
            scope.serverDisplayRating = 999;
            scope.isVehicleAllowed    = true;
            scope.maxRPM          = 0;
            scope.gearboxType     = "N/A";
            scope.gearCount       = 0;
            scope.inductionType   = "NA";
            scope.statsVisible    = true;

            scope.voteActive   = false;
            scope.voteOptions  = [];
            scope.voteTimeLeft = 0;
            scope.userVote     = null;
            scope.maxVotes     = 0;

            scope.bannerRow1     = "";
            scope.bannerRow2Pre  = "Your car is ";
            scope.bannerRow2Post = " over the allowed limit. Please lower your Performance Rating to continue.";
            scope.bannerRow3     = "Tip: try reducing engine power, tire grip, or braking force — or switch to a different car.";

            let translations = {
                banner_limit: "For fair and fun gameplay, this server limits vehicles to a Performance Rating of {limit}.",
                banner_over:  "Your car is {delta} over the allowed limit. Please lower your Performance Rating to continue.",
                banner_tip:   "Tip: try reducing engine power, tire grip, or braking force — or switch to a different car."
            };

            let voteTimer     = null;
            let voteDuration  = 60;
            let voteStartTime = 0;
            let updatePending = false;

            // =================================================================
            // UTILITIES
            // =================================================================
            function parsePayload(payload) {
                if (typeof payload === 'string') return JSON.parse(payload);
                return payload || {};
            }

            function applyTranslations() {
                scope.bannerRow1 = translations.banner_limit.replace('{limit}', scope.serverDisplayRating);
                let parts = translations.banner_over.split('{delta}');
                scope.bannerRow2Pre  = parts[0] || '';
                scope.bannerRow2Post = parts[1] || '';
                scope.bannerRow3     = translations.banner_tip;
            }

            function scheduleUpdate() {
                if (updatePending) return;
                updatePending = true;
                requestAnimationFrame(function () {
                    updatePending = false;
                    updateVisualClass();
                    scope.$apply();
                });
            }

            function updateVisualClass() {
                let rating = parseInt(scope.rating);
                let cls = rating < 100 ? 'ratingD'
                        : rating < 200 ? 'ratingC'
                        : rating < 300 ? 'ratingB'
                        :                'ratingA';
                if (!scope.isVehicleAllowed) cls += ' vehicle-denied';
                let el = document.getElementById('ratingdisplay1_1');
                if (el) el.className = 'rating-container ' + cls;
            }

            // =================================================================
            // STAT DISPLAY HELPERS
            // =================================================================
            scope.toggleStats = function () {
                scope.statsVisible = !scope.statsVisible;
            };

            scope.getBrakeClass = function () {
                if (!scope.weight || scope.weight === 0) return '';
                let m = 0.7 + (scope.brakeTorque / scope.weight / 22.05);
                return m >= 1.2 ? 'perf-maxed' : m <= 0.8 ? 'perf-low' : 'perf-medium';
            };

            scope.getGripClass = function () {
                let f = scope.avgFriction || 1.0;
                return f >= 2.5 ? 'perf-maxed' : f >= 1.5 ? 'perf-medium' : 'perf-low';
            };

            scope.getDrivetrainClass = function () {
                let dt = scope.drivetrain || 'RWD';
                return dt === 'AWD' ? 'perf-maxed' : dt === 'RWD' ? 'perf-medium' : 'perf-low';
            };

            // =================================================================
            // DATA UPDATE
            // =================================================================
            scope.updateData = function (dataJson) {
                try {
                    let d = parsePayload(dataJson);
                    scope.hp              = d.hp              || 0;
                    scope.torqueNm        = d.torqueNm        || 0;
                    scope.weight          = d.weight          || 0;
                    scope.perfPower       = d.perfPower       || 0;
                    scope.perfTorque      = d.perfTorque      || 0;
                    scope.brakeTorque     = d.brakeTorque     || 0;
                    scope.avgFriction     = d.avgFriction     || 1.0;
                    scope.drivetrain      = d.drivetrain      || "RWD";
                    scope.propulsedWheels = d.propulsedWheels || 2;
                    scope.totalWheels     = d.totalWheels     || 4;
                    scope.rating          = d.rating          || 0;
                    scope.class           = d.class           || "D";
                    scope.ratingRounded   = d.ratingRounded   || 0;
                    scope.serverMaxRating     = d.serverMaxRating     || 999;
                    scope.serverDisplayRating = d.serverDisplayRating || d.serverMaxRating || 999;
                    scope.isVehicleAllowed    = d.isVehicleAllowed !== false;
                    scope.maxRPM          = d.maxRPM          || 0;
                    scope.gearboxType     = d.gearboxType     || "N/A";
                    scope.gearCount       = d.gearCount       || 0;
                    scope.inductionType   = d.inductionType   || "NA";
                    applyTranslations();
                    scheduleUpdate();
                } catch (e) {
                    console.error('[PerformanceLimiter-UI] Error parsing data:', e);
                }
            };

            // =================================================================
            // VOTE SYSTEM
            // =================================================================
            scope.castVote = function (option) {
                if (!scope.voteActive) return;
                scope.userVote = option;
                try {
                    bngApi.engineLua(`
                        if extensions.performanceLimiter then
                            extensions.performanceLimiter.vote(${option})
                        end
                    `);
                } catch (e) {
                    console.error('[PerformanceLimiter-UI] Error casting vote:', e);
                }
            };

            scope.startVote = function (dataJson) {
                try {
                    let d = parsePayload(dataJson);
                    scope.voteActive  = true;
                    scope.userVote    = null;
                    voteDuration      = d.duration || 60;
                    voteStartTime     = Date.now() / 1000;

                    scope.voteOptions = (d.options || []).map(function (o) {
                        return { option: o, votes: 0, percentage: 0 };
                    });

                    if (voteTimer) $interval.cancel(voteTimer);
                    voteTimer = $interval(function () {
                        let elapsed = (Date.now() / 1000) - voteStartTime;
                        scope.voteTimeLeft = Math.max(0, Math.ceil(voteDuration - elapsed));
                        if (scope.voteTimeLeft <= 0) {
                            $interval.cancel(voteTimer);
                            voteTimer = null;
                            $timeout(function () {
                                if (scope.voteActive) {
                                    scope.voteActive  = false;
                                    scope.voteOptions = [];
                                    scope.userVote    = null;
                                }
                            }, 1000);
                        }
                    }, 100);

                    if (!scope.$$phase) scope.$apply();
                } catch (e) {
                    console.error('[PerformanceLimiter-UI] Error starting vote:', e);
                }
            };

            scope.updateVoteResults = function (resultsJson) {
                try {
                    let results = parsePayload(resultsJson);
                    if (!Array.isArray(results)) results = [];

                    let totalVotes = 0;
                    scope.maxVotes = 0;
                    results.forEach(function (r) {
                        totalVotes += r.votes || 0;
                        if (r.votes > scope.maxVotes) scope.maxVotes = r.votes;
                    });

                    results.forEach(function (r) {
                        let opt = scope.voteOptions.find(o => o.option === r.option);
                        if (opt) {
                            opt.votes      = r.votes || 0;
                            opt.percentage = totalVotes > 0 ? (opt.votes / totalVotes) * 100 : 0;
                        }
                    });

                    if (!scope.$$phase) scope.$apply();
                } catch (e) {
                    console.error('[PerformanceLimiter-UI] Error updating vote results:', e);
                }
            };

            scope.endVote = function (dataJson) {
                try {
                    parsePayload(dataJson);
                    scope.voteActive   = false;
                    scope.userVote     = null;
                    scope.voteOptions  = [];
                    scope.maxVotes     = 0;
                    scope.voteTimeLeft = 0;
                    if (voteTimer) { $interval.cancel(voteTimer); voteTimer = null; }
                    if (!scope.$$phase) scope.$apply();
                } catch (e) {
                    console.error('[PerformanceLimiter-UI] Error ending vote:', e);
                }
            };

            // =================================================================
            // EVENT LISTENERS
            // =================================================================
            scope.$on('PerformanceLimiterUpdateData', function (event, data) { scope.updateData(data); });
            scope.$on('PerfModVoteStarted',           function (event, data) { scope.startVote(data); });
            scope.$on('PerfModVoteUpdate',            function (event, data) { scope.updateVoteResults(data); });
            scope.$on('PerfModVoteEnded',             function (event, data) { scope.endVote(data); });

            scope.$on('PerfModTranslations', function (event, data) {
                try {
                    let t = typeof data === 'string' ? JSON.parse(data) : data;
                    if (t && typeof t === 'object') {
                        if (t.banner_limit) translations.banner_limit = t.banner_limit;
                        if (t.banner_over)  translations.banner_over  = t.banner_over;
                        if (t.banner_tip)   translations.banner_tip   = t.banner_tip;
                        applyTranslations();
                        if (!scope.$$phase) scope.$apply();
                    }
                } catch (e) {
                    console.error('[PerformanceLimiter-UI] Error applying translations:', e);
                }
            });

            let onVehicleChange = function () {
                $timeout(function () {
                    try {
                        bngApi.engineLua(`
                            if extensions.performanceLimiter then
                                local data = extensions.performanceLimiter.getVehicleData()
                                if data then
                                    guihooks.trigger('PerformanceLimiterUpdateData', jsonEncode(data))
                                end
                            end
                        `);
                    } catch (e) {
                        console.error('[PerformanceLimiter-UI] Error on vehicle change:', e);
                    }
                }, 300);
            };

            scope.$on('VehicleFocusChanged',  onVehicleChange);
            scope.$on('VehicleConfigChanged', onVehicleChange);

            scope.$on('$destroy', function () {
                updatePending     = false;
                scope.voteActive  = false;
                scope.voteOptions = [];
                scope.userVote    = null;
                if (voteTimer) { $interval.cancel(voteTimer); voteTimer = null; }
            });

            // =================================================================
            // INITIALIZATION
            // =================================================================
            applyTranslations();

            $timeout(function () {
                try {
                    bngApi.engineLua(`
                        if extensions.performanceLimiter then
                            local data = extensions.performanceLimiter.getVehicleData()
                            if data then
                                guihooks.trigger('PerformanceLimiterUpdateData', jsonEncode(data))
                            end
                            extensions.performanceLimiter.requestServerLimit()
                            if extensions.performanceLimiter.applyTranslations then
                                extensions.performanceLimiter.applyTranslations()
                            end
                        end
                    `);
                } catch (e) {
                    console.error('[PerformanceLimiter-UI] Error requesting initial data:', e);
                }
            }, 500);
        }
    };
}]);
