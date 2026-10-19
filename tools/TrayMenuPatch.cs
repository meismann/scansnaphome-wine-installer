// Patches SshTaskTray.exe so that its tray menu stays inside the working area:
//   contextMenuStrip1.Opening += ContextMenuOpening;
//   TrayMenuFix.Attach(contextMenuStrip1);              <- inserted
// See files/TrayMenuFix.cs. TrayMenuFix.dll must lie next to the patched SshTaskTray.exe.
//
// Usage: TrayMenuPatch.exe <in> <TrayMenuFix.dll> <out>
//   exit code 0 = patched, 1 = already patched, other = error
// Build: csc /r:Mono.Cecil.dll /r:Mono.Cecil.Rocks.dll /out:TrayMenuPatch.exe TrayMenuPatch.cs
using System;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;
using Mono.Cecil.Rocks;

class TrayMenuPatch
{
    const string WrapperType = "SshTaskTray.NotifyIconWrapper";
    const string MenuField = "contextMenuStrip1";

    static int Main(string[] args)
    {
        if (args.Length != 3)
        {
            Console.Error.WriteLine("usage: <in> <TrayMenuFix.dll> <out>");
            return 2;
        }
        var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(args[0])));
        var mod = ModuleDefinition.ReadModule(args[0], new ReaderParameters { AssemblyResolver = resolver });
        if (mod.AssemblyReferences.Any(r => r.Name == "TrayMenuFix"))
        {
            Console.WriteLine("already patched");
            return 1;
        }

        var ctor = mod.GetType(WrapperType).Methods.Single(m => m.IsConstructor && !m.IsStatic);
        var instructions = ctor.Body.Instructions;
        // ldarg.0; ldfld contextMenuStrip1; ...; callvirt ToolStripDropDown::add_Opening
        var addOpening = instructions.Single(i => i.OpCode == OpCodes.Callvirt
            && ((MethodReference)i.Operand).Name == "add_Opening");
        var loadMenu = instructions.Single(i => i.OpCode == OpCodes.Ldfld
            && ((FieldReference)i.Operand).Name == MenuField
            && i.Offset < addOpening.Offset && i.Next.Next.OpCode == OpCodes.Ldftn);

        var fix = ModuleDefinition.ReadModule(args[1]);
        var attach = mod.ImportReference(fix.GetType("TrayMenuFix").Methods.Single(m => m.Name == "Attach"));
        ctor.Body.SimplifyMacros(); // long branch forms, so the inserted bytes cannot overflow short branches
        var il = ctor.Body.GetILProcessor();
        var call = il.Create(OpCodes.Call, attach);
        il.InsertAfter(addOpening, call);
        il.InsertAfter(addOpening, il.Create(OpCodes.Ldfld, (FieldReference)loadMenu.Operand));
        il.InsertAfter(addOpening, il.Create(OpCodes.Ldarg_0));
        ctor.Body.OptimizeMacros();
        mod.Write(args[2]);
        Console.WriteLine("patched");
        return 0;
    }
}
