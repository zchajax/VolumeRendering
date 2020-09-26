using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class OutlineRender : MonoBehaviour
{
    void OnDrawGizmosSelected()
    {
        Gizmos.color = Color.green;
        Gizmos.DrawWireCube(transform.position, transform.localScale);
    }
}
