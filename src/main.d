module main;

import dagon;
import game;

void main(string[] args)
{
    MyGame game = New!MyGame(1280, 720, false, "Dagon Demo", args);
    game.run();
    Delete(game);
    logDebug("Leaked memory: ", allocatedMemory, " byte(s)");
}
