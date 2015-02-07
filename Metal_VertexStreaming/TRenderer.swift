//------------------------------------------------------------------------------
//  derived from Apple's WWDC example "MetalVertexStreaming"
//  Created by Jim Wrenholt on 12/6/14.
//------------------------------------------------------------------------------
import Foundation
import UIKit
import Metal
import QuartzCore

//------------------------------------------------------------------------------
// Metal Renderer for Metal Vertex Streaming sample.
// Acts as the update and render delegate for the view controller
// and performs rendering.
// Renders a simple basic triangle with 
// and updates the vertices every frame 
// using a shared CPU/GPU memory buffer.
//------------------------------------------------------------------------------
let kMaxBufferBytesPerFrame = 1024*1024
let kInFlightCommandBuffers = 3


//------------------------------------------------------------------------------
struct V4f
{
    var x:Float = 0
    var y:Float = 0
    var z:Float = 0
    var w:Float = 0
    init (_ x:Float, _ y:Float, _ z:Float, _ w:Float)
    {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
    //---------------------------------------------------------
    subscript(index:Int) -> Float
        {
        get
        {
            assert((index >= 0) && (index < 3))
            switch (index)
            {
            case 0: return x
            case 1: return y
            case 2: return z
            case 3: return w
            default: return 0
            }
        }
        set
        {
            assert((index >= 0) && (index < 3))
            switch (index)
            {
            case 0: x = newValue
            case 1: y = newValue
            case 2: z = newValue
            case 3: w = newValue
            default: z = newValue
            }
        }
    }
    //---------------------------------------------------------
}
//------------------------------------------------------------------------------
struct V3f
{
    var x:Float = 0
    var y:Float = 0
    var z:Float = 0
    init (_ x:Float, _ y:Float, _ z:Float)
    {
        self.x = x
        self.y = y
        self.z = z
    }
    //---------------------------------------------------------
    subscript(index:Int) -> Float
        {
        get
        {
            assert((index >= 0) && (index < 3))
            switch (index)
            {
            case 0: return x
            case 1: return y
            case 2: return z
            default: return 0
            }
        }
        set
        {
            assert((index >= 0) && (index < 3))
            switch (index)
            {
            case 0: x = newValue
            case 1: y = newValue
            case 2: z = newValue
            default: z = newValue
            }
        }
    }
    //---------------------------------------------------------
}
//------------------------------------------------------------------------------
var vertexData:[V4f] = [
    V4f(-1.0, -1.0, 0.0, 1.0),
    V4f(-1.0,  1.0, 0.0, 1.0),
    V4f( 1.0, -1.0, 0.0, 1.0),
    
    V4f( 1.0, -1.0, 0.0, 1.0),
    V4f(-1.0,  1.0, 0.0, 1.0),
    V4f( 1.0,  1.0, 0.0, 1.0),
    
    V4f(-0.0,   0.25, 0.0, 1.0 ),
    V4f(-0.25, -0.25, 0.0, 1.0),
    V4f( 0.25, -0.25, 0.0, 1.0),
]
//------------------------------------------------------------------------------
var vertexColorData:[V4f] = [
    V4f( 0.0, 0.0, 1.0, 1.0 ),
    V4f( 0.0, 0.0, 1.0, 1.0 ),
    V4f( 0.0, 0.0, 1.0, 1.0 ),
    
    V4f( 0.0, 0.0, 1.0, 1.0 ),
    V4f( 0.0, 0.0, 1.0, 1.0 ),
    V4f( 0.0, 0.0, 1.0, 1.0 ),
    
    V4f( 0.0, 0.0, 1.0, 1.0 ),
    V4f( 0.0, 1.0, 0.0, 1.0 ),
    V4f( 1.0, 0.0, 0.0, 1.0 ),
]
//------------------------------------------------------------------------------
// Current animated triangle offsets.
var xOffset = V3f( -1.0, 1.0, -1.0 )
var yOffset = V3f(  1.0, 0.0, -1.0 )

// Current vertex deltas
var xDelta = V3f( 0.02, -0.01, 0.03 )
var yDelta = V3f( 0.01,  0.02, -0.01 )


//------------------------------------------------------------------------------
class TRenderer :  MetalViewProtocol, TViewControllerDelegate
{
    //------------------------------------------------------------
    // renderer will create a default device at init time.
    //------------------------------------------------------------
    var device:MTLDevice?
    
    let sizeof_vData = 36 * sizeof(Float)
    //------------------------------------------------------------
    // this value will cycle from 0 to g_max_inflight_buffers whenever
    // a display completes ensuring renderer clients
    // can synchronize between g_max_inflight_buffers count buffers,
    // and thus avoiding a constant buffer from being overwritten between draws
    //------------------------------------------------------------
    var constantDataBufferIndex:Int = 0
    
    //------------------------------------------------------------
    // These queries exist so the View can initialize a
    // framebuffer that matches the expectations of the renderer
    //------------------------------------------------------------
    var depthPixelFormat:MTLPixelFormat?
    var stencilPixelFormat:MTLPixelFormat?
    var sampleCount:Int = 0
    
    //--------------------------------------------------------------------------
    //  Metal Renderer for Metal Vertex Streaming sample.
    //  Acts as the update and render delegate for the view controller
    //  and performs rendering. Renders a simple basic triangle with and
    //  updates the vertices every frame using a shared CPU/GPU memory buffer.
    //--------------------------------------------------------------------------
    var commandQueue:MTLCommandQueue?
    var defaultLibrary:MTLLibrary?
    let inflightSemaphore = dispatch_semaphore_create(kInFlightCommandBuffers)
    
    // render stage
    var pipelineState:MTLRenderPipelineState?
    var vertexBuffer:MTLBuffer?
    var vertexColorBuffer:MTLBuffer?
    
    //--------------------------------------------------------------------------
    init()
    {
        sampleCount = 4
        depthPixelFormat = MTLPixelFormat.Invalid
        stencilPixelFormat = MTLPixelFormat.Invalid
        //------------------------------------------------------------
        // find a usable Device
        //------------------------------------------------------------
        device = MTLCreateSystemDefaultDevice()
        //------------------------------------------------------------
        // create a new command queue
        //------------------------------------------------------------
        commandQueue = device!.newCommandQueue()
        
        defaultLibrary = device!.newDefaultLibrary()
        
        if (defaultLibrary == nil)
        {
            //------------------------------------------------------------
            // assert here becuase if the shader libary isnt loading,
            // its good place to debug why shaders arent compiling
            //------------------------------------------------------------
            assert(false, ">> ERROR: Couldnt create a default shader library")
        }
        
        constantDataBufferIndex = 0
        inflightSemaphore = dispatch_semaphore_create(kInFlightCommandBuffers)
    }
    //--------------------------------------------------------------------------
    // mark RENDER VIEW DELEGATE METHODS
    //--------------------------------------------------------------------------
    func configure(view:TView)
    {
        //------------------------------------------------------------
        // load all assets before triggering rendering
        //------------------------------------------------------------
        view.depthPixelFormat   = depthPixelFormat!
        view.stencilPixelFormat = stencilPixelFormat!
        view.sampleCount        = sampleCount
        
        // load the vertex program into the library
        let vertexProgram = defaultLibrary!.newFunctionWithName("passThroughVertex")
        
        // load the fragment program into the library
        let fragmentProgram = defaultLibrary!.newFunctionWithName("passThroughFragment")
        
        if (vertexProgram == nil)
        {
            println(">> ERROR: Couldnt load vertex function from default library")
        }
        if (fragmentProgram == nil)
        {
            println(">> ERROR: Couldnt load fragment function from default library")
        }
        //------------------------------------------------------------
        // set the vertex shader and buffers defined in the shader source,
        // in this case we have 2 inputs. A position buffer and a color buffer
        // Allocate a buffer to store vertex position data (we'll quad buffer this one)
        //------------------------------------------------------------
        vertexBuffer = device!.newBufferWithLength( kMaxBufferBytesPerFrame, options: nil)
        vertexBuffer!.label = "Vertices"
        
        //------------------------------------------------------------
        // Single static buffer for color information
        //------------------------------------------------------------
        vertexColorBuffer = device!.newBufferWithBytes(vertexColorData,
            length: sizeof_vData,
            options: nil)
        vertexColorBuffer!.label = "colors"
        
        //------------------------------------------------------------
        //  create a reusable pipeline state
        //------------------------------------------------------------
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.label = "MyPipeline"
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .BGRA8Unorm
        pipelineStateDescriptor.sampleCount      = sampleCount
        pipelineStateDescriptor.vertexFunction   = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        
        var pipelineError : NSError?
        pipelineState = device!.newRenderPipelineStateWithDescriptor(
            pipelineStateDescriptor, error: &pipelineError)
    }
    //--------------------------------------------------------------------------
    func renderTriangle(renderEncoder:MTLRenderCommandEncoder, view:TView, name:String)
    {
        renderEncoder.pushDebugGroup(name)

        //  set context state
        renderEncoder.setRenderPipelineState(pipelineState!)
        
        renderEncoder.setVertexBuffer(
            vertexBuffer!,
            offset: Int(256 * constantDataBufferIndex),
            atIndex: Int(0) )
        
        renderEncoder.setVertexBuffer(vertexColorBuffer!,
            offset: 0,
            atIndex: 1)
        
        //------------------------------------------------------------
        // tell the render context we want to draw our primitives
        //------------------------------------------------------------
        renderEncoder.drawPrimitives(MTLPrimitiveType.Triangle,
            vertexStart: 0,
            vertexCount: 9,
            instanceCount: 1)
        
        renderEncoder.popDebugGroup()
    }
    //--------------------------------------------------------------------------
    func render(view:TView)
    {
        dispatch_semaphore_wait(inflightSemaphore, DISPATCH_TIME_FOREVER)
        
        //------------------------------------------------------------
        // create a new command buffer for each renderpass to the current drawable
        //------------------------------------------------------------
        let commandBuffer = commandQueue!.commandBuffer()
        
        //------------------------------------------------------------
        // create a render command encoder so we can render into something
        //------------------------------------------------------------
        let renderPassDescriptor:MTLRenderPassDescriptor? = view.renderPassDescriptor()
        
        if (renderPassDescriptor != nil)
        {
            let renderEncoder:MTLRenderCommandEncoder? =
            commandBuffer.renderCommandEncoderWithDescriptor(renderPassDescriptor!)
            
            renderTriangle(renderEncoder!, view:view, name:"Triangle")
            renderEncoder!.endEncoding()
            
            //------------------------------------------------------------------
            // call the view's completion handler which is required by
            // the view since it will signal its semaphore and set up the next buffer
            //------------------------------------------------------------------
            commandBuffer.addCompletedHandler {
                [weak self] commandBuffer in
                if let strongSelf = self
                {
                    dispatch_semaphore_signal(strongSelf.inflightSemaphore)
                }
            }
            //------------------------------------------------------------------
            // commandBuffer
            //------------------------------------------------------------------
            // schedule a present once the framebuffer is complete
            let view_drawable = view.currentDrawable()!
            let mtl_drawable = view_drawable as MTLDrawable
            
            commandBuffer.presentDrawable(mtl_drawable)
            
            // finalize rendering here. this will push the command buffer to the GPU
            commandBuffer.commit()
        }
        else
        {
            // release the semaphore to keep things synchronized even if we couldnt render
            dispatch_semaphore_signal(inflightSemaphore)
        }
        
        // the renderview assumes it can now increment the buffer index
        // and that the previous index wont be touched
        // until we cycle back around to the same index
        constantDataBufferIndex = (constantDataBufferIndex + 1) % kInFlightCommandBuffers
    }
    //--------------------------------------------------------------------------
    func reshape(view:TView)
    {
        // unused in this sample
    }
    //--------------------------------------------------------------------------
    // mark VIEW CONTROLLER DELEGATE METHODS
    //--------------------------------------------------------------------------
    func update(controller:TViewController)
    {
        var bufferPointer = vertexBuffer!.contents()
        
        var vData:UnsafeMutablePointer<Void> =
        bufferPointer + 256 * constantDataBufferIndex
        
        // reset the vertex data in the shared cpu/gpu buffer
        // each frame and just accumulate offsets below
        memcpy(vData, vertexData, UInt(sizeof_vData))
        
        //------------------------------------------------------------------
        // Animate triangle offsets
        //------------------------------------------------------------------
        var vDataV4f = UnsafeMutablePointer<V4f>(vData)
        
        for (var j:Int = 0; j < 3; j++)
        {
            xOffset[j] += xDelta[j]
            if (xOffset[j] >= 1.0 || xOffset[j] <= -1.0)
            {
                xDelta[j] = -xDelta[j]
                xOffset[j] += xDelta[j]
            }
            
            yOffset[j] += yDelta[j]
            if (yOffset[j] >= 1.0 || yOffset[j] <= -1.0)
            {
                yDelta[j] = -yDelta[j]
                yOffset[j] += yDelta[j]
            }
            
            //------------------------------------------------------------------
            // Update last triangle position directly in the shared cpu/gpu buffer
            //------------------------------------------------------------------
            vDataV4f[6+j].x = xOffset[j]
            vDataV4f[6+j].y = yOffset[j]
        }
    }
    //--------------------------------------------------------------------------
    func viewController(controller:TViewController, willPause:Bool)
    {
        // timer is suspended/resumed
        // Can do any non-rendering related background work here when suspended
    }
    //--------------------------------------------------------------------------
}