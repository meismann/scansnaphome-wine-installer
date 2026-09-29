// Forces JIT compilation of every method in the given assemblies and reports InvalidProgramException,
// so broken IL from a patch is found before ScanSnap Home crashes on it.
//
// Usage (working directory = folder of the assemblies): JitCheck.exe <files...>
// Build: csc /platform:x86 /out:JitCheck.exe JitCheck.cs
using System;
using System.Reflection;
using System.Runtime.CompilerServices;

class JitCheck
{
    static int Main(string[] args)
    {
        int bad = 0, ok = 0;
        foreach (var f in args)
        {
            Assembly asm = Assembly.LoadFrom(f);
            Type[] types;
            try { types = asm.GetTypes(); }
            catch (ReflectionTypeLoadException e) { types = Array.FindAll(e.Types, t => t != null); }
            foreach (var t in types)
            {
                if (t.IsGenericTypeDefinition) continue;
                const BindingFlags all = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
                    | BindingFlags.Static | BindingFlags.DeclaredOnly;
                foreach (MethodBase m in t.GetMethods(all)) Check(f, t, m, ref ok, ref bad);
                foreach (MethodBase m in t.GetConstructors(all)) Check(f, t, m, ref ok, ref bad);
            }
        }
        Console.WriteLine("jitted {0}, invalid {1}", ok, bad);
        return bad == 0 ? 0 : 1;
    }

    static void Check(string f, Type t, MethodBase m, ref int ok, ref int bad)
    {
        if (m.IsAbstract || m.ContainsGenericParameters || m.GetMethodBody() == null) return;
        try { RuntimeHelpers.PrepareMethod(m.MethodHandle); ok++; }
        catch (InvalidProgramException) { bad++; Console.WriteLine("INVALID {0}: {1}.{2}", f, t.FullName, m.Name); }
        catch (Exception) { } // unresolved dependencies etc. are not what is tested here
    }
}
