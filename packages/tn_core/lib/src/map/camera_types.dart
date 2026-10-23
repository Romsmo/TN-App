/// The speed-camera namespace of the Trafficnetwork ("Hazard types" in the server API docs). These types only ever
/// surface through the camera path: the user's switch, the country policy and the legal notice decide whether the app
/// shows or offers them.
const List<String> cameraTypes = [
  'fixedSpeedCamera',
  'mobileSpeedCamera',
  'trailerCamera',
  'redLightCamera',
  'distanceControl',
];

/// The one filter key that stands for all camera types (one chip, not five).
const String camerasGroup = 'cameras';

bool isCameraType(String type) => cameraTypes.contains(type);

/// Whether a type is switched off by the filter: by its own key, or - for cameras - by the group key.
bool isTypeHidden(String type, Set<String> hidden) =>
    hidden.contains(type) || (isCameraType(type) && hidden.contains(camerasGroup));

/// Marker colours per hazard type. Distinct hues that stay readable on light and dark backgrounds; unknown types are grey.
const Map<String, String> hazardColors = {
  'traffic': '#E8590C',
  'ice': '#1C7ED6',
  'accident': '#C92A2A',
  'construction': '#F59F00',
  'breakdown': '#7048E8',
  'obstacle': '#0CA678',
  'fixedSpeedCamera': '#862E9C',
  'mobileSpeedCamera': '#862E9C',
  'trailerCamera': '#862E9C',
  'redLightCamera': '#862E9C',
  'distanceControl': '#862E9C',
  'cameras': '#862E9C',
};
const String unknownHazardColor = '#868E96';

String hazardColor(String type) => hazardColors[type] ?? unknownHazardColor;

/// Icon names (Material icon names are chosen by the app from these keys).
const Map<String, String> hazardIconKeys = {
  'traffic': 'car',
  'accident': 'warning',
  'construction': 'construct',
  'ice': 'snow',
  'breakdown': 'build',
  'obstacle': 'alert-circle',
  'fixedSpeedCamera': 'camera',
  'mobileSpeedCamera': 'camera',
  'trailerCamera': 'camera',
  'redLightCamera': 'camera',
  'distanceControl': 'camera',
  'cameras': 'camera',
  'zone': 'scan-circle',
};

String hazardIconKey(String type) => hazardIconKeys[type] ?? 'alert-circle';
