// import 'dart:async';
// import 'dart:collection';
// import 'dart:convert';

// ignore_for_file: unused_import, prefer_conditional_assignment

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bananokeeper/api/account_api.dart';
import 'package:bananokeeper/api/account_history_response.dart';
import 'package:bananokeeper/api/state_block.dart';
import 'package:bananokeeper/db/dbManager.dart';
import 'package:bananokeeper/providers/get_it_main.dart';
import 'package:bananokeeper/providers/wallets_service.dart';
import 'package:bananokeeper/utils/utils.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nanodart/nanodart.dart';

class Account extends ChangeNotifier {
  late int index;
  late String address;
  late String name;
  late String balance;
  late String representative;
  bool opened = false;
  int lastUpdate; //date of last update
  Account(this.index, this.name, this.address, this.balance, this.lastUpdate,
      this.representative);

  setIndex(int newIndex) {
    index = newIndex;
    notifyListeners();
  }

  int getIndex() {
    return index;
  }

  setBalance(String newBalance) {
    int activeWallet = services<WalletsService>().activeWallet;
    String originalName =
        services<WalletsService>().wallets[activeWallet].original_name;
    services<DBManager>().updateAccountBalance(originalName, index, newBalance);
    balance = newBalance;
    // print("-------------------------------- setBalance: $balance");
    notifyListeners();
  }

  String getBalance() {
    return balance;
  }

  setAddress(String newAddress) {
    address = newAddress;
    notifyListeners();
  }

  String getAddress() {
    return address;
  }

  void setName(String newName) {
    name = newName;
    notifyListeners();
  }

  String getName() {
    return name;
  }

  void setRep(String newRep) {
    int activeWallet = services<WalletsService>().activeWallet;
    String originalName =
        services<WalletsService>().wallets[activeWallet].original_name;
    services<DBManager>().updateAccountRep(originalName, index, newRep);
    representative = newRep;
    notifyListeners();
  }

  String getRep() {
    return representative;
  }

  void setLastUpdate(int time) {
    int activeWallet = services<WalletsService>().activeWallet;
    String originalName =
        services<WalletsService>().wallets[activeWallet].original_name;
    services<DBManager>()
        .updateAccountTime(originalName, index, time.toString());
    lastUpdate = time;

    notifyListeners();
  }

  int getLastUpdate() {
    return lastUpdate;
  }

///////////////////////////////////////////
  List<AccountHistory> history = [];

  bool completed = false;
  List res = [];
  Map<String, dynamic> overviewResp = {};
  getHistory() async {
    var historyRes = await AccountAPI().getHistory(getAddress(), 8);
    // "ban_14xjizffqiwjamztn4edhmbinnaxuy4fzk7c7d6gywxigydrrxftp4qgzabh",
    // 8);

    res = jsonDecode(historyRes.body);
    // print('------------------------------------------------------------');
  }

  handleResponse() {
    print("handleResponse $completed");
    try {
      if (res.isNotEmpty || res != null) {
        var _history = history;
        for (var row in res) {
          String hash = row['hash'];
          String address = row['address'] ?? "";
          String type = row['type'];
          int height = row['height'];
          int timestamp = row['timestamp'];
          String date = row['date'];
          String amountRaw = row['amountRaw'] ?? "";
          num amount = row['amount'] ?? num.parse("0");
          String newRep = row['newRepresentative'] ?? "";
          AccountHistory t = AccountHistory(hash, address, type, height,
              timestamp, date, amountRaw, amount, newRep);

          if (kDebugMode) {}
          _history.add(t);
        }
        history = List.from(_history);
      }
    } catch (e) {
      if (kDebugMode) {
        print("err handleResponse: $e");
      }
    }
    completed = true;
    notifyListeners();
  }

  onRefreshUpdateHistory() async {
    await getHistory();

    var _history = history;
    if (res == null || res.length == 0) return;
    res.reversed.forEach((row) {
      var exist = false;
      AccountHistory t = AccountHistory(
          row['hash'],
          row['address'] ?? "",
          row['type'],
          row['height'],
          row['timestamp'],
          row['date'],
          row['amountRaw'] ?? "",
          row['amount'] ?? num.parse("0"),
          row['newRepresentative'] ?? "");
      _history.forEach((element) {
        if (element.height == t.height) {
          exist = true;
        }
      });
      if (!exist) {
        _history.insert(0, t);
        exist = false;
      }
    });
    history = List.from(_history);

    notifyListeners();
  }

  getOverview([forceUpdate = false]) async {
    DateTime now = DateTime.now();
    var currentTime =
        int.parse((now.millisecondsSinceEpoch / 1000).toStringAsFixed(0));

    if ((currentTime - lastUpdate) > 60 || forceUpdate) {
      var overview = await AccountAPI().getOverview(getAddress());
      // "ban_14xjizffqiwjamztn4edhmbinnaxuy4fzk7c7d6gywxigydrrxftp4qgzabh");

      overviewResp = jsonDecode(overview.body);

      if (kDebugMode) {
        print(
            '----------------------getOverview $forceUpdate--------------------------------------');
        print("getOverview: $overviewResp");
      }
    }
  }

  bool hasReceivables = false;
  handleOverviewResponse([forceUpdate = false]) async {
    try {
      DateTime now = DateTime.now();
      var currentTime =
          int.parse((now.millisecondsSinceEpoch / 1000).toStringAsFixed(0));
      if ((currentTime - lastUpdate) > 60 || forceUpdate) {
        if (overviewResp.isNotEmpty || overviewResp != null) {
          opened = overviewResp['opened'] ?? false;
          hasReceivables = (overviewResp['receivable'] > 0);
          if (hasReceivables && !opened) {
            if (kDebugMode) {
              print(
                  "Account is not opened yet, we have receivable, starting open process...");
            }
            openAcc();
          }
          if (opened) {
            String newBalance = overviewResp['balanceRaw'];

            if (kDebugMode) {
              print(
                  'ACCOUNT: handleOverviewResponse: get Balance from resp ${newBalance}');
              // print(getBalance() != newBalance);
            }
            String newRep = overviewResp['representative'];
            if (getBalance() != newBalance) {
              setBalance(newBalance);

              if (kDebugMode) {
                print(
                    'ACCOUNT: handleOverviewResponse: newBalance ${newBalance} -> ${Utils().amountFromRaw(getBalance())}');
              }
            }
            if (getRep() != newRep) {
              setRep(newRep);
            }
            setLastUpdate(int.parse(currentTime.toString()));

            //get receivables
            if (hasReceivables) {
              //get blocks data
              var recRes = await AccountAPI().getReceivables(address);

              //latest hash
              var hist = await AccountAPI().getHistory(address, 1);
              var historyData = jsonDecode(hist.body);
              String previous = historyData[0]['hash'];

              var data = jsonDecode(recRes.body);

              for (var row in data) {
                var receivableHash = row['hash'];
                var receivableRaw = row['amountRaw'];

                var newRaw =
                    (BigInt.parse(newBalance) + BigInt.parse(receivableRaw))
                        .toString();

                int accountType = NanoAccountType.BANANO;
                String calculatedHash = NanoBlocks.computeStateHash(
                    accountType,
                    address,
                    previous,
                    representative,
                    BigInt.parse(newRaw),
                    receivableHash);

                int activeWallet = services<WalletsService>().activeWallet;
                String privateKey = services<WalletsService>()
                    .wallets[activeWallet]
                    .getPrivateKey(index);
                // Signing a block
                String sign =
                    NanoSignatures.signBlock(calculatedHash, privateKey);

                StateBlock sendBlock = StateBlock(address, previous,
                    representative, newRaw, receivableHash, sign);

                var res = await AccountAPI()
                    .processRequest(sendBlock.toJson(), "receive");

                newBalance = Decimal.tryParse(newRaw).toString();

                setBalance(newBalance);
                previous = jsonDecode(res)['hash'];
                await onRefreshUpdateHistory();
                notifyListeners();
              }
            }

            notifyListeners();

            // print("DONE EXUCTING NOTIFYLIS");
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("HandleOVerviewResp: $e");
      }
    }
  }

  openAcc() async {
    var recRes = await AccountAPI().getReceivables(address);
    var receivablesData = jsonDecode(recRes.body);
    String amountRaw = receivablesData[0]['amountRaw'];
    String hash = receivablesData[0]['hash'];

    //def test
    String representative =
        "ban_1moonanoj76om1e9gnji5mdfsopnr5ddyi6k3qtcbs8nogyjaa6p8j87sgid";
    //for open state
    String previous = "".padLeft(64, "0");

    int activeWallet = services<WalletsService>().activeWallet;
    String privateKey =
        services<WalletsService>().wallets[activeWallet].getPrivateKey(index);

    if (kDebugMode) {
      print("private key $privateKey");
    }
    int accountType = NanoAccountType.BANANO;
    String calculatedHash = NanoBlocks.computeStateHash(accountType, address,
        previous, representative, BigInt.parse(amountRaw), hash);
    // Signing a block
    String sign = NanoSignatures.signBlock(calculatedHash, privateKey);

    // print(sign);

    StateBlock openBlock =
        StateBlock(address, previous, representative, amountRaw, hash, sign);

    String hashResponse =
        await AccountAPI().processRequest(openBlock.toJson(), "open");
    // if (kDebugMode) {
    //   print(hashResponse);
    // }
    // too add to list
    onRefreshUpdateHistory();
    opened = true;
  }

  toMap() {
    return {
      "index": index,
      "name": name,
      "address": address,
      "balance": balance,
      "lastUpdate": lastUpdate
    };
  }
}
