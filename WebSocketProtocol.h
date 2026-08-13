// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <juce_core/juce_core.h>
#include <string>
#include <vector>

// Message types shared between plugin (C++) and browser (TypeScript)
namespace synchain {
namespace Protocol {

enum class MessageType {
  Handshake,    // browser -> plugin: identity + project info
  Status,       // plugin -> browser: connection status
  Audio,        // plugin -> browser: Opus-encoded audio packet
  Meter,        // plugin -> browser: dBFS level readings
  Settings,     // bidirectional: audio settings sync
  GetSettings,  // browser -> plugin: request current settings
  SetSettings,  // browser -> plugin: change encoder settings
  SetVolume,    // browser -> plugin: set master gain (0..200 pct) —— 让网页也能控制 VST 主控音量参数
  Ping,         // plugin -> browser: keep-alive
  Pong,         // browser -> plugin: keep-alive response
  Error,        // plugin -> browser: error notification
  Disconnect,   // plugin -> browser: clean shutdown notice
  Unknown
};

MessageType parseType(const juce::String& type);

// Handshake (browser -> plugin)
struct Handshake {
  juce::String projectId;
  juce::String userId;
  juce::String username;

  juce::var toJson() const;
  static Handshake fromJson(const juce::var& json);
};

// Status response (plugin -> browser)
struct StatusMessage {
  bool connected;
  juce::String pluginName;
  juce::String version;
  int volume = 100; // 当前主控音量（0..200 pct），网页据此初始化 DAW 音量条与插件同步

  juce::var toJson() const;
};

// Audio packet (plugin -> browser)
struct AudioMessage {
  uint32_t seq;
  uint64_t timestamp;
  int sampleRate;
  int channels;
  int frameSize;
  std::vector<uint8_t> opusData; // raw Opus bytes

  juce::var toJson() const;
};

// Meter levels (plugin -> browser)
struct MeterMessage {
  float left;   // dBFS
  float right;  // dBFS
  float peak;   // dBFS peak hold

  juce::var toJson() const;
};

// Audio settings (bidirectional)
struct SettingsMessage {
  int sampleRate;
  int bufferSize;
  int channels;
  int opusBitrate;
  double latencyMs = 0.0; // 可选新增（桥#2 契约 §二.6）；旧客户端忽略

  juce::var toJson() const;
  static SettingsMessage fromJson(const juce::var& json);
};

// Error (plugin -> browser)
struct ErrorMessage {
  juce::String code;
  juce::String message;

  juce::var toJson() const;
};

// Serialize top-level message with type field
juce::String serialize(const juce::var& message);
juce::var parseMessage(const juce::String& json);

} // namespace Protocol
} // namespace synchain
