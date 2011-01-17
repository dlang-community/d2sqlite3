/+

Test module for DDoc2LaTeX.

Please say something.

Author:
    Nicolas Sicard

+/
module test;

import std.stdio;

/++
Traite un tableau de données.

Cette importante fonction traite un tableau de données et revoie
une chaîne contenant les données traitées. En case d'impossibilité
de traiter les données, le second paramètre est fixé à faux.

Params:
    array = le tableau de données à traiter
    rescue = l'indicateur de réussite

Examples:
---
double[] my_data = [5.1, 7.9, 1.2, 1.0, 4.3];
bool ok;
auto result = go_and_return(my_data, ok);
---
+/
string go_and_return(in double[] array, out bool rescue)
{
    return "this";
}

void main() {
}