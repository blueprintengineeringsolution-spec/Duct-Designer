import 'package:hvac_engine/hvac_engine.dart';

DuctNode blankProject() => const DuctNode(
      id: 'ahu',
      name: 'AHU-01',
      kind: NodeKind.ahu,
      lengthM: 3,
      children: [
        DuctNode(id: 'trunk', name: 'Trunk', kind: NodeKind.terminal, flow: 0.5, lengthM: 10),
      ],
    );

DuctNode sampleProject() => const DuctNode(
      id: 'ahu',
      name: 'AHU-01 (Supply Main)',
      kind: NodeKind.ahu,
      lengthM: 3,
      equipmentDropPa: 180,
      children: [
        DuctNode(
          id: 'trunk',
          name: 'Trunk M01',
          kind: NodeKind.trunk,
          lengthM: 12,
          junction: JunctionType.tee90,
          fittings: [Elbow()],
          children: [
            DuctNode(id: 'a', name: 'Branch East', lengthM: 8, junction: JunctionType.wye45, children: [
              DuctNode(id: 't1', name: 'Diffuser 1', kind: NodeKind.terminal, flow: 0.12, lengthM: 3, fittingC: 0.4),
              DuctNode(id: 't2', name: 'Diffuser 2', kind: NodeKind.terminal, flow: 0.12, lengthM: 4, fittingC: 0.4),
            ]),
            DuctNode(
              id: 'b',
              name: 'Branch West',
              lengthM: 18,
              shape: DuctShape.rectangular,
              fittings: [Elbow(count: 2)],
              children: [
                DuctNode(id: 't3', name: 'Diffuser 3', kind: NodeKind.terminal, flow: 0.15, lengthM: 5, fittingC: 0.4),
                DuctNode(id: 't4', name: 'Flex drop 4', kind: NodeKind.terminal, flow: 0.1, lengthM: 3, fittingC: 0.4, material: DuctMaterial.flexible, flexSlack: 0.1),
              ],
            ),
          ],
        ),
      ],
    );
