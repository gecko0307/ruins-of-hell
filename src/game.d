module game;

import dagon;
import dagon.ext.jolt;
import dagon.ext.audio;

import scene;

class MyGame: Game
{
    AudioManager audioManager;
    
    this(uint w, uint h, bool fullscreen, string title, string[] args)
    {
        super(w, h, fullscreen, title, args);
        
        if (!joltInit())
            exit();
        
        audioManager = New!AudioManager(this);
        
        currentScene = New!GameScene(this);
    }
    
    ~this()
    {
        joltShutdown();
    }
}
