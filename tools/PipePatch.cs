// Scans / patches .NET assemblies:
//   new NetNamedPipeBinding()  ->  new NetNamedPipeBinding(NetNamedPipeSecurityMode.None)
//
// Wine cannot provide Windows credentials (SSPI/NTLM) for the default transport security of
// WCF named pipes, so ScanSnap Home's processes cannot talk to each other. The .config files
// are switched to security mode "None"; this tool does the same for bindings created in code.
//
// Usage: PipePatch.exe scan <files...>   |   PipePatch.exe patch <in> <out>
// Build: csc /r:Mono.Cecil.dll /r:Mono.Cecil.Rocks.dll /out:PipePatch.exe PipePatch.cs
using System;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;
using Mono.Cecil.Rocks;

class PipePatch
{
    const string BindingType = "System.ServiceModel.NetNamedPipeBinding";

    static int Main(string[] args)
    {
        if (args.Length >= 2 && args[0] == "scan")
        {
            foreach (var f in args.Skip(1)) Scan(f);
            return 0;
        }
        if (args.Length == 3 && args[0] == "patch") return Patch(args[1], args[2]);
        Console.Error.WriteLine("usage: scan <files...> | patch <in> <out>");
        return 2;
    }

    static bool IsBindingCtor(Instruction ins, out MethodReference ctor)
    {
        ctor = ins.Operand as MethodReference;
        return ins.OpCode == OpCodes.Newobj && ctor != null && ctor.DeclaringType.FullName == BindingType;
    }

    static bool IsDefaultBindingCtor(Instruction ins)
    {
        MethodReference c;
        return IsBindingCtor(ins, out c) && c.Parameters.Count == 0;
    }

    static void Scan(string file)
    {
        ModuleDefinition mod;
        try { mod = ModuleDefinition.ReadModule(file); }
        catch { return; } // not a managed assembly
        foreach (var t in mod.GetTypes())
            foreach (var m in t.Methods.Where(x => x.HasBody))
                foreach (var ins in m.Body.Instructions)
                {
                    MethodReference c;
                    if (IsBindingCtor(ins, out c))
                        Console.WriteLine("{0}: {1} -> {2}", Path.GetFileName(file), m.FullName, c.FullName);
                }
    }

    static int Patch(string input, string output)
    {
        var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(input)));
        var mod = ModuleDefinition.ReadModule(input, new ReaderParameters { AssemblyResolver = resolver });
        int n = 0;
        foreach (var t in mod.GetTypes())
            foreach (var m in t.Methods.Where(x => x.HasBody))
            {
                if (!m.Body.Instructions.Any(IsDefaultBindingCtor)) continue;
                m.Body.SimplifyMacros(); // long branch forms, so the inserted bytes cannot overflow short branches
                var il = m.Body.GetILProcessor();
                foreach (var ins in m.Body.Instructions.ToList())
                {
                    MethodReference c;
                    if (!IsBindingCtor(ins, out c) || c.Parameters.Count != 0) continue;
                    var target = c.DeclaringType.Resolve().Methods.Single(x => x.IsConstructor && !x.IsStatic
                        && x.Parameters.Count == 1
                        && x.Parameters[0].ParameterType.FullName == "System.ServiceModel.NetNamedPipeSecurityMode");
                    // Turn the existing instruction into the ldc.i4.0 and append the newobj after it,
                    // so branch targets and exception-handler boundaries pointing at it stay valid.
                    var newobj = il.Create(OpCodes.Newobj, mod.ImportReference(target));
                    ins.OpCode = OpCodes.Ldc_I4_0; // NetNamedPipeSecurityMode.None
                    ins.Operand = null;
                    il.InsertAfter(ins, newobj);
                    n++;
                }
                m.Body.OptimizeMacros();
            }
        if (n == 0) { Console.WriteLine("nothing to patch"); return 1; }
        mod.Write(output);
        Console.WriteLine("{0} site(s) patched", n);
        return 0;
    }
}
