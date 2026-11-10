import ArgumentParser
import BudsProtocol

@main
struct MacBuds: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macbuds",
        abstract: "Control Galaxy Buds2 from macOS.",
        version: "macbuds \(BudsProtocol.version)",
        subcommands: [
            StatusCommand.self,
            NoiseCommand.self, AmbientLevelCommand.self, OneEarbudNoiseCommand.self, NoiseCycleCommand.self,
            EqualizerCommand.self, TouchCommand.self,
            CustomAmbientCommand.self, BalanceCommand.self,
            InEarDetectionCommand.self, CallAmbientCommand.self, SeamlessCommand.self, DoubleTapEdgeCommand.self,
            FindCommand.self, FitTestCommand.self, InfoCommand.self,
            ANCLevelCommand.self,
            ProbeCommand.self,
        ]
    )
}
