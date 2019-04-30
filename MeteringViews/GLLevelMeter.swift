//
//  GLLevelMeter.swift
//  echoTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/12/3.
//
//
/*
 </samplecode>
*/

import UIKit
import OpenGLES.EAGL
import OpenGLES.ES1.gl
import OpenGLES.ES1.glext
import QuartzCore
import OpenGLES.EAGLDrawable

@objc(GLLevelMeter)
class GLLevelMeter: LevelMeter {
    private var _backingWidth: GLint = 0
    private var _backingHeight: GLint = 0
    private var _context: EAGLContext!
    private var _viewRenderbuffer: GLuint = 0
    private var _viewFramebuffer: GLuint = 0
    
    override class var layerClass: AnyClass {
        return  CAEAGLLayer.self
    }
    
    @discardableResult
    private func _createFrameBuffer() -> Bool {
        glGenFramebuffersOES(1, &_viewFramebuffer)
        glGenRenderbuffersOES(1, &_viewRenderbuffer)
        
        glBindFramebufferOES(GLenum(GL_FRAMEBUFFER_OES), _viewFramebuffer)
        glBindRenderbufferOES(GLenum(GL_RENDERBUFFER_OES), _viewRenderbuffer)
        _context.renderbufferStorage(Int(GL_RENDERBUFFER_OES), from: (self.layer as! EAGLDrawable))
        glFramebufferRenderbufferOES(GLenum(GL_FRAMEBUFFER_OES), GLenum(GL_COLOR_ATTACHMENT0_OES), GLenum(GL_RENDERBUFFER_OES), _viewRenderbuffer)
        
        glGetRenderbufferParameterivOES(GLenum(GL_RENDERBUFFER_OES), GLenum(GL_RENDERBUFFER_WIDTH_OES), &_backingWidth)
        glGetRenderbufferParameterivOES(GLenum(GL_RENDERBUFFER_OES), GLenum(GL_RENDERBUFFER_HEIGHT_OES), &_backingHeight)
        
        if glCheckFramebufferStatusOES(GLenum(GL_FRAMEBUFFER_OES)) != GLenum(GL_FRAMEBUFFER_COMPLETE_OES) {
            NSLog("failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GLenum(GL_FRAMEBUFFER_OES)))
            return false
        }
        
        return true
    }
    
    private func _destroyFramebuffer() {
        glDeleteFramebuffersOES(1, &_viewFramebuffer)
        _viewFramebuffer = 0
        glDeleteRenderbuffersOES(1, &_viewRenderbuffer)
        _viewRenderbuffer = 0
        
    }
    
    private func _setupView() {
        
        // Sets up matrices and transforms for OpenGL ES
        glViewport(0, 0, _backingWidth, _backingHeight)
        glMatrixMode(GLenum(GL_PROJECTION))
        glLoadIdentity()
        glOrthof(0, GLfloat(_backingWidth), 0, GLfloat(_backingHeight), -1.0, 1.0)
        glMatrixMode(GLenum(GL_MODELVIEW))
        
        // Clears the view with black
        glClearColor(0.0, 0.0, 0.0, 1.0)
        
        glEnableClientState(GLenum(GL_VERTEX_ARRAY))
        ///glEnableClientState(GLenum(GL_TEXTURE_COORD_ARRAY))
        
    }
    
    override func _performInit() {
        _colorThresholds = [
            LevelMeterColorThreshold(maxValue: 0.6, color: UIColor(red: 0, green: 1, blue: 0, alpha: 1)),
            LevelMeterColorThreshold(maxValue: 0.9, color: UIColor(red: 1, green: 1, blue: 0, alpha: 1)),
            LevelMeterColorThreshold(maxValue: 1.0, color: UIColor(red: 1, green: 0, blue: 0, alpha: 1)),
        ]
        isVertical = self.frame.width < self.frame.height
        
        self.contentScaleFactor = UIScreen.main.scale
        _scaleFactor = self.contentScaleFactor
        
        let eaglLayer = self.layer as! CAEAGLLayer
        
        eaglLayer.isOpaque = true
        
        eaglLayer.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking: false,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
        ]
        
        _context = EAGLContext(api: .openGLES1)
        
        if _context == nil || !EAGLContext.setCurrent(_context) || !self._createFrameBuffer() {
            fatalError("cannot initialize OpenGL context")
        }
        
        self._setupView()
    }
    
    private func _drawView() {
        if _viewFramebuffer == 0 {return}
        
        // Make sure that you are drawing to the current context
        EAGLContext.setCurrent(_context)
        
        glBindFramebufferOES(GLenum(GL_FRAMEBUFFER_OES), _viewFramebuffer)
        
        bail: do {
            guard let bgc = self.bgColor?.cgColor,
                
                bgc.numberOfComponents == 4
                else {
                    break bail
            }
            
            let rgba = bgc.components!
            
            glClearColor(GLfloat(rgba[0]), GLfloat(rgba[1]), GLfloat(rgba[2]), 1.0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            
            glPushMatrix()
            
            let bds: CGRect
            
            if isVertical {
                glScalef(1.0, -1.0, 1.0)
                bds = CGRect(x: 0.0, y: -1.0, width: self.bounds.width * _scaleFactor, height: self.bounds.height * _scaleFactor)
            } else {
                glTranslatef(0.0, GLfloat(self.bounds.height * _scaleFactor), 0.0)
                glRotatef(-90.0, 0.0, 0.0, 1.0)
                bds = CGRect(x: 0.0, y: 1.0, width: self.bounds.height * _scaleFactor, height: self.bounds.width * _scaleFactor)
            }
            
            if numLights == 0 {
                var currentTop: CGFloat = 0.0
                
                for thisThresh in _colorThresholds {
                    let val = min(thisThresh.maxValue, level)
                    
                    let rect = CGRect(
                        x: 0,
                        y: bds.size.height * currentTop,
                        width: bds.size.width,
                        height: bds.size.height * (val - currentTop)
                    )
                    
                    NSLog("Drawing rect (%0.2f, %0.2f, %0.2f, %0.2f)", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
                    
                    
                    let vertices = UnsafeMutablePointer<GLfloat>.allocate(capacity: 8)
                    defer{vertices.deallocate()}
                    vertices.initialize(from: [
                        GLfloat(rect.minX), GLfloat(rect.minY),
                        GLfloat(rect.maxX), GLfloat(rect.minY),
                        GLfloat(rect.minX), GLfloat(rect.maxY),
                        GLfloat(rect.maxX), GLfloat(rect.maxY),
                        ], count: 8)
                    defer{vertices.deinitialize(count: 8)}
                    
                    let clr = thisThresh.color.cgColor
                    if clr.numberOfComponents != 4 {break bail}
                    let rgba = clr.components!
                    glColor4f(GLfloat(rgba[0]), GLfloat(rgba[1]), GLfloat(rgba[2]), GLfloat(rgba[3]))
                    
                    
                    glVertexPointer(2, GLenum(GL_FLOAT), 0, vertices)
                    glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
                    
                    
                    if level < thisThresh.maxValue {break}
                    
                    currentTop = val
                }
            } else {
                var lightMinVal: CGFloat = 0.0
                let insetAmount: CGFloat
                let lightVSpace = bds.size.height / CGFloat(numLights)
                if lightVSpace < 4.0 {insetAmount = 0.0}
                else if lightVSpace < 8.0 {insetAmount = 0.5}
                else {insetAmount = 1.0}
                
                var peakLight = -1
                if peakLevel > 0.0 {
                    peakLight = Int(peakLevel * CGFloat(numLights))
                    if peakLight >= numLights {peakLight = numLights - 1}
                }
                
                for light_i in 0..<numLights {
                    let lightMaxVal = CGFloat(light_i + 1) / CGFloat(numLights)
                    var lightIntensity: CGFloat
                    
                    if light_i == peakLight {
                        lightIntensity = 1.0
                    } else {
                        lightIntensity = (level - lightMinVal) / (lightMaxVal - lightMinVal)
                        lightIntensity = LEVELMETER_CLAMP(0.0, lightIntensity, 1.0)
                        if !variableLightIntensity && lightIntensity > 0.0 {lightIntensity = 1.0}
                    }
                    
                    var lightColor = _colorThresholds[0].color
                    for color_i in 0..<_colorThresholds.count-1 {
                        let thisThresh = _colorThresholds[color_i]
                        let nextThresh = _colorThresholds[color_i + 1]
                        if thisThresh.maxValue <= lightMaxVal {lightColor = nextThresh.color}
                    }
                    
                    var lightRect = CGRect(
                        x: 0.0,
                        y: bds.origin.y * (bds.size.height * (CGFloat(light_i) / CGFloat(numLights))),
                        width: bds.size.width,
                        height: bds.size.height * (1.0 / CGFloat(numLights))
                    )
                    lightRect = lightRect.insetBy(dx: insetAmount, dy: insetAmount)
                    
                    let vertices = UnsafeMutablePointer<GLfloat>.allocate(capacity: 8)
                    defer{vertices.deallocate()}
                    vertices.initialize(from: [
                        GLfloat(lightRect.minX), GLfloat(lightRect.minY),
                        GLfloat(lightRect.maxX), GLfloat(lightRect.minY),
                        GLfloat(lightRect.minX), GLfloat(lightRect.maxY),
                        GLfloat(lightRect.maxX), GLfloat(lightRect.maxY),
                        ], count: 8)
                    defer{vertices.deinitialize(count: 8)}
                    
                    glVertexPointer(2, GLenum(GL_FLOAT), 0, vertices)
                    
                    glColor4f(1.0, 0.0, 0.0, 1.0)
                    
                    if lightIntensity == 1.0 {
                        let clr = lightColor.cgColor
                        if clr.numberOfComponents != 4 {break bail}
                        let rgba = clr.components!
                        glColor4f(GLfloat(rgba[0]), GLfloat(rgba[1]), GLfloat(rgba[2]), GLfloat(rgba[3]))
                        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
                    } else if lightIntensity > 0.0 {
                        let clr = lightColor.cgColor
                        if clr.numberOfComponents != 4 {break bail}
                        let rgba = clr.components!
                        glColor4f(GLfloat(rgba[0]), GLfloat(rgba[1]), GLfloat(rgba[2]), GLfloat(lightIntensity))
                        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
                    }
                    
                    lightMinVal = lightMaxVal
                }
                
                
            }
            
        } /* bail: do */
        glPopMatrix()
        
        glFlush()
        glBindRenderbufferOES(GLenum(GL_RENDERBUFFER_OES), _viewRenderbuffer)
        _context.presentRenderbuffer(Int(GL_RENDERBUFFER_OES))
    }
    
    override func layoutSubviews() {
        EAGLContext.setCurrent(_context)
        self._destroyFramebuffer()
        self._createFrameBuffer()
        self._drawView()
    }
    
    override func draw(_ rect: CGRect) {
        self._drawView()
    }
    
    override func setNeedsDisplay() {
        self._drawView()
    }
    
    deinit {
        if EAGLContext.current() === _context {
            EAGLContext.setCurrent(nil)
        }
        
        _context = nil
        
    }
    
}
