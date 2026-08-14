// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "AudioMeter.h"
#include <algorithm>
#include <cmath>

namespace synchain
{

void AudioMeter::process(const float* interleavedSamples, int numSamples)
{
    if (numSamples <= 0)
        return;

    float peakL = 0.0f;
    float peakR = 0.0f;

    for (int i = 0; i < numSamples; ++i)
    {
        float absL = std::abs(interleavedSamples[i * 2]);
        float absR = std::abs(interleavedSamples[i * 2 + 1]);

        if (absL > peakL)
            peakL = absL;
        if (absR > peakR)
            peakR = absR;
    }

    mCurrentPeakLeft = peakL;
    mCurrentPeakRight = peakR;

    // Peak hold with 3-second refresh
    if (peakL > mHoldPeakLeft)
    {
        mHoldPeakLeft = peakL;
        mHoldCounter = 0;
    }
    if (peakR > mHoldPeakRight)
    {
        mHoldPeakRight = peakR;
        mHoldCounter = 0;
    }

    ++mHoldCounter;
    if (mHoldCounter >= kHoldFrames)
    {
        // 3 seconds elapsed — refresh to current instantaneous peak
        mHoldPeakLeft = peakL;
        mHoldPeakRight = peakR;
        mHoldCounter = 0;
    }
}

MeterLevels AudioMeter::getLevels() const
{
    return {
        amplitudeToDB(mCurrentPeakLeft), // left: instantaneous peak
        amplitudeToDB(mCurrentPeakRight), // right: instantaneous peak
        amplitudeToDB(std::max(mHoldPeakLeft, mHoldPeakRight)) // peak hold
    };
}

void AudioMeter::resetHold()
{
    mHoldPeakLeft = 0.0f;
    mHoldPeakRight = 0.0f;
    mHoldCounter = 0;
}

} // namespace synchain
