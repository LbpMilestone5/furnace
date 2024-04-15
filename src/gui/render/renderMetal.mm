/**
 * Furnace Tracker - multi-system chiptune tracker
 * Copyright (C) 2021-2023 tildearrow and contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

// TODO:
// - wipe
// - textures
// - maybe fix VSync

#include "renderMetal.h"
#include "backends/imgui_impl_metal.h"

#include <Metal/Metal.h>
#include <QuartzCore/QuartzCore.h>

struct FurnaceGUIRenderMetalPrivate {
  CAMetalLayer* context;
  id<MTLCommandQueue> cmdQueue;
  id<MTLCommandBuffer> cmdBuf;
  id<MTLRenderCommandEncoder> renderEncoder;
  id<CAMetalDrawable> drawable;
  MTLRenderPassDescriptor* renderPass;

  FurnaceGUIRenderMetalPrivate():
    context(NULL),
    cmdQueue(NULL),
    cmdBuf(NULL),
    renderEncoder(NULL),
    drawable(NULL),
    renderPass(NULL) {}
};

class FurnaceMetalTexture: public FurnaceGUITexture {
  public:
  id<MTLTexture> tex;
  int width, height;
  unsigned char* lockedData;
  FurnaceMetalTexture():
    tex(NULL),
    width(0),
    height(0),
    lockedData(NULL) {}
};

ImTextureID FurnaceGUIRenderMetal::getTextureID(FurnaceGUITexture* which) {
  FurnaceMetalTexture* t=(FurnaceMetalTexture*)which;
  return t->tex;
}

bool FurnaceGUIRenderMetal::lockTexture(FurnaceGUITexture* which, void** data, int* pitch) {
  FurnaceMetalTexture* t=(FurnaceMetalTexture*)which;
  if (t->lockedData!=NULL) return false;
  t->lockedData=new unsigned char[t->width*t->height*4];

  *data=t->lockedData;
  *pitch=t->width*4;
  return true;
}

bool FurnaceGUIRenderMetal::unlockTexture(FurnaceGUITexture* which) {
  FurnaceMetalTexture* t=(FurnaceMetalTexture*)which;
  if (t->lockedData==NULL) return false;

  [t->tex replaceRegion:MTLRegionMake2D(0,0,(NSUInteger)t->width,(NSUInteger)t->height) mipmapLevel:0 withBytes:t->lockedData bytesPerRow:(NSUInteger)t->width*4];
  delete[] t->lockedData;
  t->lockedData=NULL;

  return true;
}

bool FurnaceGUIRenderMetal::updateTexture(FurnaceGUITexture* which, void* data, int pitch) {
  FurnaceMetalTexture* t=(FurnaceMetalTexture*)which;
  [t->tex replaceRegion:MTLRegionMake2D(0,0,(NSUInteger)t->width,(NSUInteger)t->height) mipmapLevel:0 withBytes:data bytesPerRow:(NSUInteger)pitch];
  return true;
}

FurnaceGUITexture* FurnaceGUIRenderMetal::createTexture(bool dynamic, int width, int height, bool interpolate) {
  MTLTextureDescriptor* texDesc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:(NSUInteger)width height:(NSUInteger)height mipmapped:NO];
  texDesc.usage=MTLTextureUsageShaderRead;
  texDesc.storageMode=MTLStorageModeManaged;

  id<MTLTexture> texture=[priv->context.device newTextureWithDescriptor:texDesc];

  if (texture==NULL) return NULL;
  FurnaceMetalTexture* ret=new FurnaceMetalTexture;
  ret->tex=texture;
  ret->width=width;
  ret->height=height;
  return ret;
}

bool FurnaceGUIRenderMetal::destroyTexture(FurnaceGUITexture* which) {
  FurnaceMetalTexture* t=(FurnaceMetalTexture*)which;
  delete t;
  return true;
}

void FurnaceGUIRenderMetal::setTextureBlendMode(FurnaceGUITexture* which, FurnaceGUIBlendMode mode) {
}

void FurnaceGUIRenderMetal::setBlendMode(FurnaceGUIBlendMode mode) {
}

// you should only call this once!!!
void FurnaceGUIRenderMetal::clear(ImVec4 color) {
  int outW, outH;
  getOutputSize(outW,outH);
  priv->context.drawableSize=CGSizeMake(outW,outH);

  if (priv->drawable) {
    [priv->drawable release];
  }
  if (priv->cmdBuf) {
    [priv->cmdBuf release];
  }

  priv->drawable=[priv->context nextDrawable];

  priv->cmdBuf=[priv->cmdQueue commandBuffer];
  priv->renderPass.colorAttachments[0].clearColor=MTLClearColorMake(color.x,color.y,color.z,color.w);
  priv->renderPass.colorAttachments[0].texture=priv->drawable.texture;
  priv->renderPass.colorAttachments[0].loadAction=MTLLoadActionClear;
  priv->renderPass.colorAttachments[0].storeAction=MTLStoreActionStore;
  priv->renderEncoder=[priv->cmdBuf renderCommandEncoderWithDescriptor:priv->renderPass];
}

bool FurnaceGUIRenderMetal::newFrame() {
  return ImGui_ImplMetal_NewFrame(priv->renderPass);
}

bool FurnaceGUIRenderMetal::canVSync() {
  return swapIntervalSet;
}

void FurnaceGUIRenderMetal::createFontsTexture() {
  ImGui_ImplMetal_CreateFontsTexture(priv->context.device);
}

void FurnaceGUIRenderMetal::destroyFontsTexture() {
  ImGui_ImplMetal_DestroyFontsTexture();
}

void FurnaceGUIRenderMetal::renderGUI() {
  ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(),priv->cmdBuf,priv->renderEncoder);
}

void FurnaceGUIRenderMetal::wipe(float alpha) {
  // TODO
}

void FurnaceGUIRenderMetal::present() {
  [priv->renderEncoder endEncoding];

  [priv->cmdBuf presentDrawable:priv->drawable];
  [priv->cmdBuf commit];

  [priv->renderEncoder release];
}

bool FurnaceGUIRenderMetal::getOutputSize(int& w, int& h) {
  return SDL_GetRendererOutputSize(sdlRend,&w,&h)==0;
}

int FurnaceGUIRenderMetal::getWindowFlags() {
  return 0;
}

void FurnaceGUIRenderMetal::setSwapInterval(int swapInterval) {
  if (SDL_RenderSetVSync(sdlRend,(swapInterval>=0)?1:0)!=0) {
    swapIntervalSet=false;
    logW("tried to enable VSync but couldn't!");
  } else {
    swapIntervalSet=true;
  }
}

void FurnaceGUIRenderMetal::preInit() {
  SDL_SetHint(SDL_HINT_RENDER_DRIVER,"metal");
  priv=new FurnaceGUIRenderMetalPrivate;
}

bool FurnaceGUIRenderMetal::init(SDL_Window* win, int swapInterval) {
  SDL_SetHint(SDL_HINT_RENDER_DRIVER,"metal");

  sdlRend=SDL_CreateRenderer(win,-1,SDL_RENDERER_ACCELERATED|SDL_RENDERER_PRESENTVSYNC|SDL_RENDERER_TARGETTEXTURE);

  if (sdlRend==NULL) return false;

  if (SDL_RenderSetVSync(sdlRend,(swapInterval>=0)?1:0)!=0) {
    swapIntervalSet=false;
    logW("tried to enable VSync but couldn't!");
  } else {
    swapIntervalSet=true;
  }

  logI("retrieving context...");

  priv->context=(__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(sdlRend);

  if (priv->context==NULL) {
    logE("Metal layer is NULL!");
    return false;
  }

  priv->context.pixelFormat=MTLPixelFormatBGRA8Unorm;

  priv->cmdQueue=[priv->context.device newCommandQueue];
  priv->renderPass=[MTLRenderPassDescriptor new];
  return true;
}

void FurnaceGUIRenderMetal::initGUI(SDL_Window* win) {
  ImGui_ImplMetal_Init(priv->context.device);
  ImGui_ImplSDL2_InitForMetal(win);
}

void FurnaceGUIRenderMetal::quitGUI() {
  ImGui_ImplMetal_Shutdown();
}

bool FurnaceGUIRenderMetal::quit() {
  if (sdlRend==NULL) return false;
  [priv->renderPass release];
  [priv->cmdQueue release];
  SDL_DestroyRenderer(sdlRend);
  sdlRend=NULL;
  return true;
}
