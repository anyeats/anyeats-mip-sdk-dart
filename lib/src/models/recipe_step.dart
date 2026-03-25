/// Recipe step model for drink recipe process configuration
///
/// Used with command 0x1D (setDrinkRecipeProcess) and related operations.

/// Water type for drink operations
enum WaterType {
  hot(0x00),
  cold(0x01);

  final int code;
  const WaterType(this.code);
}

/// Recipe step operation types (OPT-N values for 0x1D command)
enum RecipeOperationType {
  none(0x00),
  instantChannel(0x01),
  grinding(0x02),
  cupDispense(0x03),
  iceMaking(0x04),
  lidPlacement(0x05),
  lidPressing(0x06),
  independentMixing(0x07);

  final int code;
  const RecipeOperationType(this.code);
}

/// A single step in a drink recipe process
/// Used with command 0x1D (setDrinkRecipeProcess)
class RecipeStep {
  final RecipeOperationType operationType;
  final List<int> parameters; // OPI-N bytes

  const RecipeStep({required this.operationType, required this.parameters});

  /// Create an instant channel step (OPT=0x01)
  /// This is the main step for dispensing powder + water
  ///
  /// [channel] - Channel number (0-based, 0 = 1st channel)
  /// [waterType] - Hot or cold water
  /// [materialDuration] - Powder dispensing time in 0.1s units (0-999)
  /// [waterAmount] - Water amount in 0.1mL units (0-999), must be >= materialDuration when using time unit
  /// [materialSpeed] - Powder dispensing speed 0-100%
  /// [mixSpeed] - Stirring speed 0-100%
  /// [subChannel] - Sub-material channel (-1 to 127, -1 = none)
  /// [subMaterialDuration] - Sub-material dispensing time in 0.1s units (0-999)
  /// [subMaterialSpeed] - Sub-material speed 0-100%
  /// [endWaitTime] - Wait time after step completes, in seconds (0-255)
  factory RecipeStep.instantChannel({
    required int channel,
    WaterType waterType = WaterType.hot,
    int materialDuration = 0,
    int waterAmount = 0,
    int materialSpeed = 50,
    int mixSpeed = 0,
    int subChannel = -1,
    int subMaterialDuration = 0,
    int subMaterialSpeed = 0,
    int endWaitTime = 0,
  }) {
    return RecipeStep(
      operationType: RecipeOperationType.instantChannel,
      parameters: [
        channel & 0xFF,
        waterType.code,
        (materialDuration >> 8) & 0xFF, materialDuration & 0xFF,
        (waterAmount >> 8) & 0xFF, waterAmount & 0xFF,
        materialSpeed & 0xFF,
        mixSpeed & 0xFF,
        subChannel & 0xFF,
        (subMaterialDuration >> 8) & 0xFF, subMaterialDuration & 0xFF,
        subMaterialSpeed & 0xFF,
        endWaitTime & 0xFF,
      ],
    );
  }

  /// Create a cup dispense step (OPT=0x03)
  ///
  /// [dispenser] - 0=manual wait, 1=#1 dispenser, 2=#2 dispenser
  factory RecipeStep.cupDispense({int dispenser = 1}) {
    return RecipeStep(
      operationType: RecipeOperationType.cupDispense,
      parameters: [dispenser & 0xFF],
    );
  }

  /// Create a grinding step (OPT=0x02, fresh ground coffee)
  ///
  /// [channel] - Grinder channel (0-based)
  /// [waterTemp] - Grinding water temperature 70-90C
  /// [grindDuration] - Grind time in 0.1s units (20-200)
  /// [waterAmount] - Water amount in g/mL (20-200)
  /// [makeType] - 0=concurrent with instant, 1=sequential
  factory RecipeStep.grinding({
    int channel = 0,
    int waterTemp = 85,
    int grindDuration = 50,
    int waterAmount = 50,
    int makeType = 1,
  }) {
    return RecipeStep(
      operationType: RecipeOperationType.grinding,
      parameters: [
        channel & 0xFF,
        waterTemp & 0xFF,
        grindDuration & 0xFF,
        waterAmount & 0xFF,
        makeType & 0xFF,
      ],
    );
  }

  /// Create an ice making step (OPT=0x04)
  ///
  /// [channel] - Ice channel (0-based)
  /// [weight] - Ice weight in grams (0-200)
  factory RecipeStep.iceMaking({int channel = 0, int weight = 100}) {
    return RecipeStep(
      operationType: RecipeOperationType.iceMaking,
      parameters: [channel & 0xFF, weight & 0xFF, 0x00], // 3 bytes per protocol
    );
  }

  /// Create a lid placement step (OPT=0x05)
  ///
  /// [channel] - Lid dispenser channel (0-based)
  factory RecipeStep.lidPlacement({int channel = 0}) {
    return RecipeStep(
      operationType: RecipeOperationType.lidPlacement,
      parameters: [channel & 0xFF],
    );
  }

  /// Create a lid pressing step (OPT=0x06)
  ///
  /// [channel] - Press channel (0-based)
  factory RecipeStep.lidPressing({int channel = 0}) {
    return RecipeStep(
      operationType: RecipeOperationType.lidPressing,
      parameters: [channel & 0xFF],
    );
  }

  /// Create an independent mixing step (OPT=0x07, GS801 only)
  ///
  /// [channel] - Mixer channel (0-based)
  /// [mixType] - 0=fixed position, 1=fixed stir-stop, 2=centrifugal, 3=centrifugal stir-stop, 4=concentric layered
  /// [maxSpeed] - Maximum mixing speed 1-100%
  factory RecipeStep.independentMixing({
    int channel = 0,
    int mixType = 0,
    int maxSpeed = 50,
  }) {
    return RecipeStep(
      operationType: RecipeOperationType.independentMixing,
      parameters: [channel & 0xFF, mixType & 0xFF, maxSpeed & 0xFF],
    );
  }

  /// Encode this step as bytes for the 0x1D command
  /// Returns [OPT, OP-DL, ...OPI] bytes
  List<int> toBytes() {
    return [
      operationType.code,
      parameters.length,
      ...parameters,
    ];
  }
}
