// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <cmath>

namespace synchain
{

struct MeterLevels
{
    float left = -60.0f; // dBFS
    float right = -60.0f;
    float peak = -60.0f; // peak hold
};

class AudioMeter
{
public:
    AudioMeter() = default;

    // Process a stereo interleaved buffer and update levels.
    void process(const float* interleavedSamples, int numSamples);

    MeterLevels getLevels() const;
    void resetHold();

private:
    float mCurrentPeakLeft = 0.0f;
    float mCurrentPeakRight = 0.0f;
    float mHoldPeakLeft = 0.0f;
    float mHoldPeakRight = 0.0f;
    int mHoldCounter = 0;

    static constexpr int kHoldFrames = 60; // 3s at ~20 updates/sec

    static float amplitudeToDB(float amplitude)
    {
        if (amplitude < 1e-10f)
            return -60.0f;
        return 20.0f * std::log10(amplitude);
    }
};

} // namespace synchain
