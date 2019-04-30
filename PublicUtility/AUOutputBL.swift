//
//  AUOutputBL.swift
//  echoTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/12/2.
//
//
/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 TPart of CoreAudio Utility Classes.
*/

import AVFoundation

// ____________________________________________________________________________
//
//	AUOutputBL - Simple Buffer List wrapper targetted to use with retrieving AU output
// Works in one of two ways (both adjustable)... Can use it with NULL pointers, or allocate
// memory to receive the data in.

// Before using this with any call to AudioUnitRender, it needs to be Prepared
// as some calls to AudioUnitRender can reset the ABL

class AUOutputBL {
    
    func prepare() throws {
        try prepare(mFrames)
    }
    
    var abl: UnsafeMutableAudioBufferListPointer? {return mBufferList}
    
    var allocatedFrames: Int {return mFrames}
    
    var format: CAStreamBasicDescription {return mFormat}
    
    private var allocatedBytes: Int {return mBufferSize * mNumberBuffers}
    
    private let mFormat: CAStreamBasicDescription
    private var mBufferMemory = UnsafeMutableRawBufferPointer(start: nil, count: 0)
    private var mBufferList: UnsafeMutableAudioBufferListPointer
    private var mNumberBuffers: Int
    private var mBufferSize: Int
    private var mFrames: Int
    
    // don't want to copy these.. can if you want, but more code to write!
    //	AUOutputBL () {}
    //	AUOutputBL (const AUOutputBL &c);
    //	AUOutputBL& operator= (const AUOutputBL& c);
    
    /*
     struct AudioBufferList
     {
     UInt32		mNumberBuffers;
     AudioBuffer	mBuffers[1];
     };
     struct AudioBuffer
     {
     UInt32	mNumberChannels;	//	number of interleaved channels in the buffer
     UInt32	mDataByteSize;		//	the size of the buffer pointed to by mData
     void*	mData;				//	the pointer to the buffer
     };
     */
    
    // this is the constructor that you use
    // it can't be reset once you've constructed it
    init(_ inDesc: CAStreamBasicDescription, _ inDefaultNumFrames: Int) {
        mFormat = inDesc
        mBufferMemory = .init(start: nil, count: 0)
        mBufferSize = 0
        mFrames = inDefaultNumFrames
        
        mNumberBuffers = mFormat.isInterleaved ? 1 : mFormat.numberChannels
        mBufferList = AudioBufferList.allocate(maximumBuffers: mNumberBuffers)
    }
    
    deinit {
        if mBufferMemory.baseAddress != nil {
            mBufferMemory.deallocate()
        }
        
        free(mBufferList.unsafeMutablePointer) //### `AudioBufferList.allocate(maximumBuffers:)` requests allocated region to be freed by `free()`.
    }
    
    // this version can throw if this is an allocted ABL and inNumFrames is > AllocatedFrames()
    // you can set the bool to true if you want a NULL buffer list even if allocated
    // inNumFrames must be a valid number (will throw if inNumFrames is 0)
    func prepare(_ inNumFrames: Int, _ inWantNullBufferIfAllocated: Bool = false) throws {
        let channelsPerBuffer = mFormat.isInterleaved ? mFormat.numberChannels : 1
        
        if mBufferMemory.baseAddress == nil || inWantNullBufferIfAllocated {
            mBufferList.count = mNumberBuffers
            for i in 0..<mNumberBuffers {
                mBufferList[i].mNumberChannels = UInt32(channelsPerBuffer)
                mBufferList[i].mDataByteSize = UInt32(mFormat.framesToBytes(inNumFrames))
                mBufferList[i].mData = nil
            }
        } else {
            let nBytes = mFormat.framesToBytes(inNumFrames)
            if nBytes * mNumberBuffers > allocatedBytes {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_TooManyFramesToProcess))
            }
            
            mBufferList.count = mNumberBuffers
            var p = mBufferMemory.baseAddress!
            for i in 0..<mNumberBuffers {
                mBufferList[i].mNumberChannels = UInt32(channelsPerBuffer)
                mBufferList[i].mDataByteSize = UInt32(nBytes)
                mBufferList[i].mData = p
                p += mBufferSize
            }
        }
    }
    
    
    // You only need to call this if you want to allocate a buffer list
    // if you want an empty buffer list, just call Prepare()
    // if you want to dispose previously allocted memory, pass in 0
    // then you either have an empty buffer list, or you can re-allocate
    // Memory is kept around if an Allocation request is less than what is currently allocated
    func allocate(_ inNumFrames: Int) {
        if inNumFrames != 0 {
            var nBytes = mFormat.framesToBytes(inNumFrames)
            
            if nBytes <= allocatedBytes {
                return
            }
            
            // align successive buffers for Altivec and to take alternating
            // cache line hits by spacing them by odd multiples of 16
            if mNumberBuffers > 1 {
                nBytes = (nBytes + (0x10 - (nBytes & 0xF))) | 0x10
            }
            
            mBufferSize = nBytes
            
            let memorySize = mBufferSize * mNumberBuffers
            let newMemory = UnsafeMutableRawBufferPointer.allocate(byteCount: memorySize, alignment: 1)
            newMemory.baseAddress!.initializeMemory(as: UInt8.self, repeating: 0, count: memorySize)
            
            let oldMemory = mBufferMemory
            mBufferMemory = newMemory
            oldMemory.deallocate()
            
            mFrames = inNumFrames
        } else {
            if mBufferMemory.baseAddress != nil {
                mBufferMemory.deallocate()
                mBufferMemory = .init(start: nil, count: 0)
            }
            mBufferSize = 0
            mFrames = 0
        }
    }
    
    //#if DEBUG
    func print() {
        Swift.print("AUOutputBL::Print")
        mFormat.print()
        Swift.print(String(format: "Num Buffers:%d, mFrames:%d, allocatedMemory:%@\n", mBufferList.count, mFrames, (mBufferMemory.baseAddress != nil ? "T" : "F")))
        for i in mBufferList.indices {
            let buf = mBufferList[i]
            Swift.print(String(format: "\tBuffer:%d, Size:%d, Chans:%d, Buffer:%p\n", i, buf.mDataByteSize, buf.mNumberChannels, UInt(bitPattern: buf.mData)))
        }
    }
    //#endif
    
}
