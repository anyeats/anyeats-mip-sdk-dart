part of '../main.dart';

/// Channel tab (executeChannel 0x25) and Recipe tab (setDrinkRecipeProcess 0x1D + makeDrink 0x01)
extension ChannelPanelBuilder on _CoffeeMachineScreenState {

  // ========== Channel Panel (executeChannel 0x25) ==========

  Widget _buildChannelPanel() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('executeChannel (0x25) - 직접 실행', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        _buildChannelButton('Make 1 (1번통)', '1번 채널 단독, 온수', [0], WaterType.hot),
        const Divider(),
        _buildChannelButton('Make 1&2 (1+2번통)', '1번→2번 배출 후 교반, 온수', [0, 1], WaterType.hot),
        const Divider(),
        _buildChannelButton('Make 3&2 (3+2번통)', '3번→2번 배출 후 교반, 온수', [2, 1], WaterType.hot),
        const Divider(height: 24, thickness: 2),
        _buildChannelButton('Make 1 Cold (1번통)', '1번 채널 단독, 냉수', [0], WaterType.cold),
        const Divider(),
        _buildChannelButton('Make 1&2 Cold', '1번→2번 배출 후 교반, 냉수', [0, 1], WaterType.cold),
        const Divider(),
        _buildChannelButton('Make 3&2 Cold', '3번→2번 배출 후 교반, 냉수', [2, 1], WaterType.cold),
      ],
    );
  }

  Widget _buildChannelButton(String title, String subtitle, List<int> channels, WaterType waterType) {
    final isHot = waterType == WaterType.hot;
    return ListTile(
      dense: true,
      leading: Icon(isHot ? Icons.local_cafe : Icons.local_drink, color: isHot ? Colors.red : Colors.blue),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      trailing: ElevatedButton(
        onPressed: () => _executeChannels(channels, waterType),
        style: ElevatedButton.styleFrom(backgroundColor: isHot ? Colors.red[100] : Colors.blue[100]),
        child: const Text('Make'),
      ),
    );
  }

  Future<void> _executeChannels(List<int> channels, WaterType waterType) async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final chNames = channels.map((c) => '${c + 1}번통').join('+');
      for (int i = 0; i < channels.length; i++) {
        final ch = channels[i];
        final isLast = i == channels.length - 1;
        _addEventLog('Executing ch$ch (${ch + 1}번통)...');
        await _gs805.executeChannel(
          channel: ch,
          waterType: waterType,
          materialDuration: 50,     // 문서 예시값: 5초
          waterAmount: 50,          // 문서 예시값: 5초
          materialSpeed: 0,         // 문서 예시값
          mixSpeed: 0,              // 문서 예시값
        );
      }
      _showSnackBar('$chNames 실행 완료', Colors.blue);
    } catch (e) {
      _showSnackBar('Failed: $e', Colors.red);
    }
  }

  // ========== Recipe Panel (setDrinkRecipeProcess 0x1D + makeDrink 0x01) ==========

  Widget _buildRecipePanel() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('setDrinkRecipeProcess (0x1D) + makeDrink (0x01)', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        _buildRecipeButton('Recipe 1 (1번통)', 'hotDrink1에 1번 채널 레시피 설정 후 제조', DrinkNumber.hotDrink1, WaterType.hot, [0]),
        const Divider(),
        _buildRecipeButton('Recipe 1&2 (1+2번통)', 'hotDrink2에 1번→2번 레시피 설정 후 제조', DrinkNumber.hotDrink2, WaterType.hot, [0, 1]),
        const Divider(),
        _buildRecipeButton('Recipe 3&2 (3+2번통)', 'hotDrink3에 3번→2번 레시피 설정 후 제조', DrinkNumber.hotDrink3, WaterType.hot, [2, 1]),
        const Divider(height: 24, thickness: 2),
        _buildRecipeButton('Recipe 1 Cold', 'coldDrink1에 레시피 설정', DrinkNumber.coldDrink1, WaterType.cold, [0]),
        const Divider(),
        _buildRecipeButton('Recipe 1&2 Cold', 'coldDrink2에 레시피 설정', DrinkNumber.coldDrink2, WaterType.cold, [0, 1]),
        const Divider(),
        _buildRecipeButton('Recipe 3&2 Cold', 'coldDrink3에 레시피 설정', DrinkNumber.coldDrink3, WaterType.cold, [2, 1]),
        const Divider(height: 24, thickness: 2),
        // --- 0x15 레시피 시간 설정 ---
        ListTile(
          dense: true,
          leading: const Icon(Icons.timer, color: Colors.teal),
          title: const Text('0x15 레시피 시간 설정 → Make'),
          subtitle: const Text('ch1: 재료1초, ch2: 물20초'),
          trailing: ElevatedButton(
            onPressed: () async {
              if (!_isConnected) return;
              try {
                // ch1~8: (material, water) in 0.1s units
                final times = <(int, int)>[
                  (10, 0),      // ch1: 재료만 1초
                  (0, 200),     // ch2: 물만 20초
                  (0, 0),       // ch3
                  (0, 0),       // ch4
                  (0, 0),       // ch5
                  (0, 0),       // ch6
                  (0, 0),       // ch7
                  (0, 0),       // ch8
                ];
                _addEventLog('0x15: ch1(mat=10) ch2(wat=200)...');
                await _gs805.setDrinkRecipeTime(DrinkNumber.hotDrink1, times);
                _addEventLog('0x15 OK. Making...');
                await _gs805.makeDrink(DrinkNumber.hotDrink1);
                _showSnackBar('0x15 → Make 완료', Colors.blue);
              } catch (e) {
                _showSnackBar('Failed: $e', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[100]),
            child: const Text('Run'),
          ),
        ),
        const Divider(height: 24, thickness: 2),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('채널 조합 테스트', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown)),
        ),
        _build015Test('ch1 물만', [(0,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch2 물만', [(0,0),(0,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch3 물만', [(0,0),(0,0),(0,100),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1재료 + ch1물', [(10,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1재료 + ch2물', [(10,0),(0,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1재료 + ch3물', [(10,0),(0,0),(0,100),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1,ch3재료 + ch2물', [(10,0),(0,100),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1,ch3재료 + ch4물', [(10,0),(0,0),(10,0),(0,100),(0,0),(0,0),(0,0),(0,0)]),
        // ch1=물 + 다른채널=재료 테스트
        _build015Test('ch1물 + ch2재료', [(0,100),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1물 + ch3재료', [(0,100),(0,0),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1물 + ch4재료', [(0,100),(0,0),(0,0),(10,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1물 + ch3,ch4재료', [(0,100),(0,0),(10,0),(10,0),(0,0),(0,0),(0,0),(0,0)]),
        // 1번통(ch1) 재료+물 테스트: 원래 값 유지 시도
        const Divider(height: 24, thickness: 2),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('1번통 재료+물 테스트', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
        ),
        _build015Test('ch1(재료10,물100)', [(10,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1재료10만 (VendApp복구후)', [(10,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1물100만 (VendApp복구후)', [(0,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('전체1: ch1(10,100)나머지(1,1)', [(10,100),(1,1),(1,1),(1,1),(1,1),(1,1),(1,1),(1,1)]),
        // --- 냉음료 (coldDrink1) 테스트 ---
        const Divider(height: 24, thickness: 2),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('냉음료 테스트 (coldDrink1)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
        ),
        _build015Test('Cold: ch1물100만', [(0,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)], drink: DrinkNumber.coldDrink1),
        _build015Test('Cold: ch1재료10만', [(10,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)], drink: DrinkNumber.coldDrink1),
        _build015Test('Cold: ch1물 + ch2재료', [(0,100),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)], drink: DrinkNumber.coldDrink1),
        _build015Test('Cold: ch1물 + ch3재료', [(0,100),(0,0),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0)], drink: DrinkNumber.coldDrink1),
        _build015Test('Cold: ch1물 + ch2,ch3재료', [(0,100),(10,0),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0)], drink: DrinkNumber.coldDrink1),
      ],
    );
  }

  Widget _build015Test(String label, List<(int, int)> times, {DrinkNumber drink = DrinkNumber.hotDrink1}) {
    return ListTile(
      dense: true,
      leading: Icon(Icons.science, color: drink.isHot ? Colors.brown : Colors.blue),
      title: Text(label),
      trailing: ElevatedButton(
        onPressed: () async {
          if (!_isConnected) return;
          try {
            _addEventLog('0x15: $label (${drink.displayName})');
            await _gs805.setDrinkRecipeTime(drink, times);
            await _gs805.makeDrink(drink);
            _addEventLog('makeDrink OK → polling start');
            _startDrinkStatusPolling();
          } catch (e) {
            _showSnackBar('Failed: $e', Colors.red);
          }
        },
        child: const Text('Run'),
      ),
    );
  }

  Widget _buildRecipeButton(String title, String subtitle, DrinkNumber drink, WaterType waterType, List<int> channels) {
    final isHot = waterType == WaterType.hot;
    return ListTile(
      dense: true,
      leading: Icon(isHot ? Icons.local_cafe : Icons.local_drink, color: isHot ? Colors.orange : Colors.cyan),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      trailing: ElevatedButton(
        onPressed: () => _setRecipeAndMake(drink, waterType, channels),
        style: ElevatedButton.styleFrom(backgroundColor: isHot ? Colors.orange[100] : Colors.cyan[100]),
        child: const Text('Make'),
      ),
    );
  }

  Future<void> _setRecipeAndMake(DrinkNumber drink, WaterType waterType, List<int> channels) async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final steps = <RecipeStep>[
        RecipeStep.cupDispense(dispenser: 0), // 수동 컵 배치 대기
      ];
      for (final ch in channels) {
        final isLast = ch == channels.last;
        steps.add(RecipeStep.instantChannel(
          channel: ch,
          waterType: waterType,
          materialDuration: 10,
          waterAmount: isLast ? 2000 : 10,  // WD >= MD 필수
          materialSpeed: 50,
          mixSpeed: isLast && channels.length > 1 ? 100 : 0,
        ));
      }

      final chNames = channels.map((c) => '${c + 1}번통').join('+');

      // 디버깅: 보내는 바이트 로그
      final cmdBytes = steps.expand((s) => s.toBytes()).toList();
      final hexStr = cmdBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      _addEventLog('Recipe bytes: [${drink.code.toRadixString(16)}] $hexStr');

      _addEventLog('Setting recipe: ${drink.displayName} ($chNames)...');
      try {
        await _gs805.setDrinkRecipeProcess(drink, steps);
        _addEventLog('Recipe set OK (RSTA=0x00)');
      } catch (e) {
        _addEventLog('Recipe set FAILED: $e');
        _showSnackBar('Recipe failed: $e', Colors.red);
        return;
      }
      _addEventLog('Making ${drink.displayName}...');
      await _gs805.makeDrink(drink);
      _showSnackBar('$chNames 제조 시작', Colors.blue);
      _startDrinkStatusPolling();
    } catch (e) {
      _showSnackBar('Failed: $e', Colors.red);
    }
  }
}
