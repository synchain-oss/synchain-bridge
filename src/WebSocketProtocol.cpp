// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "WebSocketProtocol.h"

namespace synchain
{
namespace Protocol
{

MessageType parseType(const juce::String& type)
{
    if (type == "handshake")
        return MessageType::Handshake;
    if (type == "status")
        return MessageType::Status;
    if (type == "audio")
        return MessageType::Audio;
    if (type == "meter")
        return MessageType::Meter;
    if (type == "settings")
        return MessageType::Settings;
    if (type == "get_settings")
        return MessageType::GetSettings;
    if (type == "set_settings")
        return MessageType::SetSettings;
    if (type == "set_volume")
        return MessageType::SetVolume;
    if (type == "ping")
        return MessageType::Ping;
    if (type == "pong")
        return MessageType::Pong;
    if (type == "error")
        return MessageType::Error;
    if (type == "disconnect")
        return MessageType::Disconnect;
    return MessageType::Unknown;
}

// -- Handshake --

juce::var Handshake::toJson() const
{
    auto* obj = new juce::DynamicObject();
    obj->setProperty("type", "handshake");
    obj->setProperty("projectId", projectId);
    obj->setProperty("userId", userId);
    obj->setProperty("username", username);
    return juce::var(obj);
}

Handshake Handshake::fromJson(const juce::var& json)
{
    Handshake h;
    h.projectId = json["projectId"].toString();
    h.userId = json["userId"].toString();
    h.username = json["username"].toString();
    return h;
}

// -- Status --

juce::var StatusMessage::toJson() const
{
    auto* obj = new juce::DynamicObject();
    obj->setProperty("type", "status");
    obj->setProperty("connected", connected);
    obj->setProperty("pluginName", pluginName);
    obj->setProperty("version", version);
    obj->setProperty("volume", volume);
    obj->setProperty("contract", contract);
    return juce::var(obj);
}

// -- Audio --

juce::var AudioMessage::toJson() const
{
    auto* obj = new juce::DynamicObject();
    obj->setProperty("type", "audio");
    obj->setProperty("seq", static_cast<int>(seq));
    obj->setProperty("timestamp", static_cast<int64_t>(timestamp));
    obj->setProperty("sampleRate", sampleRate);
    obj->setProperty("channels", channels);
    obj->setProperty("frameSize", frameSize);
    obj->setProperty("data", juce::Base64::toBase64(opusData.data(), opusData.size()));
    return juce::var(obj);
}

// -- Meter --

juce::var MeterMessage::toJson() const
{
    auto* obj = new juce::DynamicObject();
    obj->setProperty("type", "meter");
    obj->setProperty("left", left);
    obj->setProperty("right", right);
    obj->setProperty("peak", peak);
    return juce::var(obj);
}

// -- Settings --

juce::var SettingsMessage::toJson() const
{
    auto* obj = new juce::DynamicObject();
    obj->setProperty("type", "settings");
    obj->setProperty("sampleRate", sampleRate);
    obj->setProperty("bufferSize", bufferSize);
    obj->setProperty("channels", channels);
    obj->setProperty("opusBitrate", opusBitrate);
    obj->setProperty("latencyMs", latencyMs);
    return juce::var(obj);
}

SettingsMessage SettingsMessage::fromJson(const juce::var& json)
{
    SettingsMessage s;
    s.sampleRate = static_cast<int>(json["sampleRate"]);
    s.bufferSize = static_cast<int>(json["bufferSize"]);
    s.channels = static_cast<int>(json["channels"]);
    s.opusBitrate = static_cast<int>(json["opusBitrate"]);
    s.latencyMs = json.hasProperty("latencyMs") ? static_cast<double>(json["latencyMs"]) : 0.0;
    return s;
}

// -- Error --

juce::var ErrorMessage::toJson() const
{
    auto* obj = new juce::DynamicObject();
    obj->setProperty("type", "error");
    obj->setProperty("code", code);
    obj->setProperty("message", message);
    return juce::var(obj);
}

// -- Top-level helpers --

juce::String serialize(const juce::var& message)
{
    return juce::JSON::toString(message, false);
}

juce::var parseMessage(const juce::String& json)
{
    return juce::JSON::parse(json);
}

} // namespace Protocol
} // namespace synchain
