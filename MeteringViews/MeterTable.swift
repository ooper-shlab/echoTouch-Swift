//
//  MeterTable.swift
//  echoTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/12/3.
//
//
/*
 </samplecode>
*/

import Foundation

class MeterTable {

    func valueAt(_ inDecibels: Float) -> Float {
        if inDecibels < mMinDecibels {return 0.0}
        if inDecibels >= 0.0 {return 1.0}
        let index = Int(inDecibels * mScaleFactor)
        return mTable[index]
    }
    private var mMinDecibels: Float
    private var mDecibelResolution: Float
    private var mScaleFactor: Float
    private var mTable: [Float]

    private func dbToAmp(_ inDb: Double) -> Double { return pow(10.0, 0.05 * inDb) }

    // MeterTable constructor arguments:
    // inNumUISteps - the number of steps in the UI element that will be drawn.
    //					This could be a height in pixels or number of bars in an LED style display.
    // inTableSize - The size of the table. The table needs to be large enough that there are no large gaps in the response.
    // inMinDecibels - the decibel value of the minimum displayed amplitude.
    // inRoot - this controls the curvature of the response. 2.0 is square root, 3.0 is cube root. But inRoot doesn't have to be integer valued, it could be 1.8 or 2.5, etc.
    init?(_ inMinDecibels: Float = -80.0, _ inTableSize: Int = 400, _ inRoot: Float = 2.0) {
        mMinDecibels = inMinDecibels
        mDecibelResolution = mMinDecibels / Float(inTableSize - 1)
        mScaleFactor = 1.0 / mDecibelResolution

        if inMinDecibels >= 0.0 {
            print("MeterTable inMinDecibels must be negative")
            return nil
        }

        mTable = Array(repeating: 0.0, count: inTableSize)

        let minAmp = dbToAmp(Double(inMinDecibels))
        let ampRange = 1.0 - minAmp
        let invAmpRange = 1.0 / ampRange

        let rroot = 1.0 / Double(inRoot)
        for i in 0..<inTableSize {
            let  decibels = Double(i) * Double(mDecibelResolution)
            let amp = dbToAmp(decibels)
            let adjAmp = (amp - minAmp) * invAmpRange
            mTable[i] = Float(pow(adjAmp, rroot))
        }
    }

}
